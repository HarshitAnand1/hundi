import { erc20Abi, type Hash, type Hex, type LocalAccount } from "viem";
import {
  invoiceKey,
  invoiceNumberHash,
  selfRelayCartVerifier,
  signAcceptance,
  verifyCart,
  verifyInvoice,
  type Acceptance,
  type BuyerPolicy,
  type CartView,
  type PurchaseOrder,
  type Terms,
  type VendorRecord,
  type VerifyCartResult,
  type VerifyInvoiceInput,
  type VerifyInvoiceResult,
} from "@hundi/sdk";
import { reads, type Chainish } from "../chain.js";
import type { Store } from "../store.js";

/**
 * Buyer agent (A2A payment role). Every decision is a deterministic check from @hundi/sdk;
 * nothing here asks a model for approval.
 */
export class BuyerAgent {
  private readonly r: ReturnType<typeof reads>;

  constructor(
    readonly account: LocalAccount,
    private readonly c: Chainish,
    private readonly store: Store,
    readonly policy: BuyerPolicy,
    private readonly vendors: Map<string, VendorRecord>,
    private readonly orders: Map<string, PurchaseOrder>,
    /** Desk merchant-of-record key trusted for self-relay carts. */
    private readonly merchant: `0x${string}`,
  ) {
    this.r = reads(c);
  }

  async review(input: VerifyInvoiceInput, now: number): Promise<VerifyInvoiceResult> {
    return verifyInvoice(input, {
      policy: this.policy,
      now,
      getVendor: (a) => this.vendors.get(a.toLowerCase()),
      getPurchaseOrder: (ref) => this.orders.get(ref),
      // Local book first, then the chain: the registry is the source of truth for single use.
      isInvoiceKeyUsed: async (k) =>
        this.store.hasInvoiceKey(k, (x) => invoiceKey(x.terms.seller, x.terms.buyer, x.acceptance.invoiceNumberHash)) ||
        (await this.r.invoiceKeyUsed(k)),
    });
  }

  /** Builds and signs the EIP-712 acceptance. The vault address comes from the factory, not the seller. */
  async accept(t: Terms, termsHash: Hex, invoiceNumber: string, now: number): Promise<{ acceptance: Acceptance; signature: Hex }> {
    const vault = await this.r.predictVault(t);
    let nonce = BigInt(now) * 1000n + BigInt(Math.floor(Math.random() * 1000));
    while (await this.r.nonceUsed(this.account.address, nonce)) nonce += 1n;
    const acceptance: Acceptance = {
      buyer: t.buyer,
      seller: t.seller,
      token: t.token,
      faceAmount: t.faceAmount,
      dueDate: t.dueDate,
      invoiceHash: t.invoiceHash,
      invoiceNumberHash: invoiceNumberHash(invoiceNumber),
      termsHash,
      vault,
      nonce,
      expiry: BigInt(now + 86_400),
    };
    const signature = await signAcceptance(this.account, acceptance, this.c.chain.id, this.c.deployment.acceptanceRegistry);
    return { acceptance, signature };
  }

  async checkCart(cart: CartView): Promise<VerifyCartResult> {
    return verifyCart(cart, {
      ...selfRelayCartVerifier(this.merchant),
      getAcceptance: (h) => {
        const rec = this.store.getByTermsHash(h);
        return rec && { terms: rec.terms, acceptance: rec.acceptance };
      },
      predictVault: (t) => this.r.predictVault(t),
      getVaultState: (v) => this.r.vaultState(v),
    });
  }

  /**
   * Pays an order only if verifyCart passes. HSP_MODE=self-relay: a direct USDC.e transfer from the
   * buyer wallet to the vault. The HSP gateway rail replaces only this transfer step.
   */
  async pay(cart: CartView): Promise<{ ok: true; tx: Hash } | { ok: false; result: VerifyCartResult }> {
    const result = await this.checkCart(cart);
    if (!result.ok) return { ok: false, result };
    const w = this.c.wallet(this.account);
    const { request } = await this.c.pub.simulateContract({
      account: this.account,
      address: this.c.deployment.token,
      abi: erc20Abi,
      functionName: "transfer",
      args: [result.vault, result.amount],
    });
    return { ok: true, tx: await this.c.confirm(await w.writeContract(request)) };
  }
}
