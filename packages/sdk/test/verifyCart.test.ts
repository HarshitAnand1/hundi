import { describe, expect, it } from "vitest";
import { keccak256, toBytes, type Address } from "viem";
import {
  CART_REFUSAL_CODES,
  hashTerms,
  invoiceNumberHash,
  selfRelayCartVerifier,
  signSelfRelayCart,
  verifyCart,
  type Acceptance,
  type CartRefusalCode,
  type CartView,
  type StoredAcceptance,
  type Terms,
  type VaultState,
  type VerifyCartDeps,
} from "../src/index.js";
import { DAY, NOW, TOKEN, USDC, buyerAcct, merchantAcct, sellerAcct, strangerAcct } from "./fixtures.js";

const VAULT: Address = "0x6666666666666666666666666666666666666666";
const terms: Terms = {
  seller: sellerAcct.address,
  buyer: buyerAcct.address,
  token: TOKEN,
  faceAmount: 10_000n * USDC,
  dueDate: BigInt(NOW + 73 * DAY),
  invoiceHash: keccak256(toBytes("inv")),
  advanceBps: 9000,
  feeAnnualBps: 800,
  lateAnnualBps: 1800,
  bondBps: 200,
  protocolFeeBps: 10,
  graceSeconds: BigInt(3 * DAY),
  defaultSeconds: BigInt(30 * DAY),
  pool: "0x4444444444444444444444444444444444444444",
  protocolTreasury: "0x5555555555555555555555555555555555555555",
};
const termsHash = hashTerms(terms);
const acceptance: Acceptance = {
  buyer: terms.buyer,
  seller: terms.seller,
  token: terms.token,
  faceAmount: terms.faceAmount,
  dueDate: terms.dueDate,
  invoiceHash: terms.invoiceHash,
  invoiceNumberHash: invoiceNumberHash("INV-2026-001"),
  termsHash,
  vault: VAULT,
  nonce: 1n,
  expiry: BigInt(NOW + 7 * DAY),
};
const stored: StoredAcceptance = { terms, acceptance };

function deps(over: Partial<VerifyCartDeps> = {}, state: VaultState = "Funded"): VerifyCartDeps {
  return {
    ...selfRelayCartVerifier(merchantAcct.address),
    getAcceptance: (h) => (h.toLowerCase() === termsHash ? stored : undefined),
    predictVault: () => VAULT,
    getVaultState: () => state,
    ...over,
  };
}

function cart(over: Partial<Omit<CartView, "cartHash" | "merchantSignature">> = {}, signer = merchantAcct) {
  return signSelfRelayCart(signer, {
    orderId: "ord-1",
    payTo: VAULT,
    token: TOKEN,
    amount: terms.faceAmount,
    termsHash,
    dueDate: terms.dueDate,
    ...over,
  });
}

const codes = (r: Awaited<ReturnType<typeof verifyCart>>) => (r.ok ? [] : r.refusals.map((x) => x.code));

type Case = { name: string; code: CartRefusalCode; also?: CartRefusalCode[]; run: () => Promise<Awaited<ReturnType<typeof verifyCart>>> };

const cases: Case[] = [
  { name: "signed by a stranger", code: "CART_SIGNATURE_INVALID", run: async () => verifyCart(await cart({}, strangerAcct), deps()) },
  {
    name: "payTo tampered after merchant signed",
    code: "CART_HASH_MISMATCH",
    also: ["PAYTO_NOT_VAULT"], // defence in depth: the vault check catches it independently
    run: async () => verifyCart({ ...(await cart()), payTo: strangerAcct.address }, deps({ verifyMerchantSignature: () => true })),
  },
  {
    name: "unknown receivable",
    code: "ACCEPTANCE_NOT_FOUND",
    run: async () => verifyCart(await cart({ termsHash: keccak256(toBytes("other")) }), deps()),
  },
  {
    name: "payee swap: merchant-signed cart pays an attacker",
    code: "PAYTO_NOT_VAULT",
    run: async () => verifyCart(await cart({ payTo: strangerAcct.address }), deps()),
  },
  {
    name: "on-chain predicted vault disagrees with stored acceptance",
    code: "PAYTO_NOT_VAULT",
    run: async () => verifyCart(await cart(), deps({ predictVault: () => strangerAcct.address })),
  },
  { name: "inflated amount", code: "AMOUNT_MISMATCH", run: async () => verifyCart(await cart({ amount: 10_500n * USDC }), deps()) },
  {
    name: "wrong token",
    code: "TOKEN_MISMATCH",
    run: async () => verifyCart(await cart({ token: "0x9999999999999999999999999999999999999999" }), deps()),
  },
  { name: "due date changed", code: "DUE_DATE_MISMATCH", run: async () => verifyCart(await cart({ dueDate: terms.dueDate + 1n }), deps()) },
  { name: "vault already settled", code: "ALREADY_SETTLED", run: async () => verifyCart(await cart(), deps({}, "Settled")) },
];

describe("verifyCart", () => {
  it("accepts a correct cart for a funded vault", async () => {
    const r = await verifyCart(await cart(), deps());
    expect(r).toEqual({ ok: true, vault: VAULT, amount: terms.faceAmount });
  });

  it("accepts a correct cart for an open (prepaid) vault", async () => {
    expect((await verifyCart(await cart(), deps({}, "Open"))).ok).toBe(true);
  });

  it.each(cases)("$code — $name", async ({ code, also, run }) => {
    expect(codes(await run())).toEqual([code, ...(also ?? [])]);
  });

  it("covers every refusal code in the spec", () => {
    expect(new Set(cases.map((c) => c.code))).toEqual(new Set(CART_REFUSAL_CODES));
  });

  it("refuses defaulted and cancelled vaults", async () => {
    for (const s of ["Defaulted", "Cancelled"] as const) {
      expect(codes(await verifyCart(await cart(), deps({}, s)))).toEqual(["ALREADY_SETTLED"]);
    }
  });

  it("a stored acceptance whose terms do not hash to it is treated as missing", async () => {
    const bad: StoredAcceptance = { terms: { ...terms, advanceBps: 9500 }, acceptance };
    expect(codes(await verifyCart(await cart(), deps({ getAcceptance: () => bad })))).toEqual(["ACCEPTANCE_NOT_FOUND"]);
  });

  it("partial-payment orders can use an injected expected amount", async () => {
    const r = await verifyCart(await cart({ amount: 4_000n * USDC }), deps({ expectedAmount: () => 4_000n * USDC }));
    expect(r.ok).toBe(true);
  });

  it("a throwing chain read fails closed", async () => {
    const r = await verifyCart(await cart(), deps({ getVaultState: () => Promise.reject(new Error("rpc down")) }));
    expect(r.ok).toBe(false);
  });
});
