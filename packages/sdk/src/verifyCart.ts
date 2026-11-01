import type { Address, Hex } from "viem";
import { hashTerms } from "./terms.js";
import type { Acceptance, Refusal, Terms, VaultState } from "./types.js";

/** HANDOFF Section 8. */
export const CART_REFUSAL_CODES = [
  "CART_SIGNATURE_INVALID",
  "CART_HASH_MISMATCH",
  "ACCEPTANCE_NOT_FOUND",
  "PAYTO_NOT_VAULT",
  "AMOUNT_MISMATCH",
  "TOKEN_MISMATCH",
  "DUE_DATE_MISMATCH",
  "ALREADY_SETTLED",
] as const;
export type CartRefusalCode = (typeof CART_REFUSAL_CODES)[number];

/**
 * Normalised view of an HSP Cart Mandate. The HSP adapter maps the real wire format into this.
 * [VERIFY] field names and cart hashing against the official HSP docs; nothing here assumes them.
 */
export interface CartView {
  orderId: string;
  payTo: Address;
  token: Address;
  amount: bigint;
  /** The receivable this order pays; carried in our order metadata. */
  termsHash: Hex;
  dueDate: bigint;
  /** Hash the merchant claims to have signed. */
  cartHash: Hex;
  merchantSignature: Hex;
}

export interface StoredAcceptance {
  terms: Terms;
  acceptance: Acceptance;
}

export interface VerifyCartDeps {
  /** Recompute the cart hash from its contents (HSP-defined; injected). */
  computeCartHash(cart: CartView): Hex | Promise<Hex>;
  /** Check the ES256K merchant_authorization over cartHash (HSP-defined; injected). */
  verifyMerchantSignature(cart: CartView): boolean | Promise<boolean>;
  /** The buyer's own stored acceptance for termsHash — never data from the cart. */
  getAcceptance(termsHash: Hex): StoredAcceptance | undefined | Promise<StoredAcceptance | undefined>;
  /** ReceivableFactory.predictVault(terms), read from chain. */
  predictVault(terms: Terms): Address | Promise<Address>;
  /** ReceivableVault.state(), read from chain. "Open" if not deployed yet. */
  getVaultState(vault: Address): VaultState | Promise<VaultState>;
  /** Amount the buyer intends to pay; defaults to faceAmount. */
  expectedAmount?(stored: StoredAcceptance): bigint | Promise<bigint>;
}

export type VerifyCartResult =
  | { ok: true; vault: Address; amount: bigint }
  | { ok: false; refusals: Refusal<CartRefusalCode>[] };

/**
 * Deterministic pre-payment check (HANDOFF 5.2 step 8). Code, not a prompt. Fails closed.
 * The payee comes from the buyer's own acceptance and the chain, never from the cart.
 */
export async function verifyCart(cart: CartView, deps: VerifyCartDeps): Promise<VerifyCartResult> {
  const refusals: Refusal<CartRefusalCode>[] = [];
  const refuse = (code: CartRefusalCode, detail: string) => refusals.push({ code, detail });
  const done = (): VerifyCartResult => ({ ok: false, refusals });

  try {
    if (!(await deps.verifyMerchantSignature(cart))) refuse("CART_SIGNATURE_INVALID", "merchant signature invalid");
    const recomputed = await deps.computeCartHash(cart);
    if (recomputed.toLowerCase() !== cart.cartHash.toLowerCase()) {
      refuse("CART_HASH_MISMATCH", "cart contents do not match the signed hash");
    }

    const stored = await deps.getAcceptance(cart.termsHash);
    if (!stored || hashTerms(stored.terms) !== stored.acceptance.termsHash.toLowerCase()
      || stored.acceptance.termsHash.toLowerCase() !== cart.termsHash.toLowerCase()) {
      refuse("ACCEPTANCE_NOT_FOUND", `no acceptance on file for ${cart.termsHash}`);
      return done();
    }
    const { terms, acceptance } = stored;

    const vault = await deps.predictVault(terms);
    if (vault !== acceptance.vault) {
      refuse("PAYTO_NOT_VAULT", `predicted vault ${vault} differs from accepted vault ${acceptance.vault}`);
    } else if (cart.payTo !== vault) {
      refuse("PAYTO_NOT_VAULT", `payTo ${cart.payTo} is not the vault ${vault}`);
    }

    const expected = deps.expectedAmount ? await deps.expectedAmount(stored) : terms.faceAmount;
    if (cart.amount !== expected) refuse("AMOUNT_MISMATCH", `amount ${cart.amount} != expected ${expected}`);
    if (cart.token !== terms.token) refuse("TOKEN_MISMATCH", `token ${cart.token} != ${terms.token}`);
    if (cart.dueDate !== terms.dueDate) refuse("DUE_DATE_MISMATCH", `due ${cart.dueDate} != ${terms.dueDate}`);

    const state = await deps.getVaultState(vault);
    if (state !== "Open" && state !== "Funded") refuse("ALREADY_SETTLED", `vault is ${state}`);
  } catch (err) {
    refuse("CART_SIGNATURE_INVALID", `verification error: ${err instanceof Error ? err.message : String(err)}`);
  }

  if (refusals.length) {
    const order = (c: CartRefusalCode) => CART_REFUSAL_CODES.indexOf(c);
    return { ok: false, refusals: refusals.sort((a, b) => order(a.code) - order(b.code)) };
  }
  return { ok: true, vault: cart.payTo, amount: cart.amount };
}
