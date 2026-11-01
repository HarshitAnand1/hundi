import { describe, expect, it } from "vitest";
import { keccak256, toBytes, type Address } from "viem";
import { acceptanceDigest, hashTerms, invoiceKey, invoiceNumberHash, type Acceptance, type Terms } from "../src/index.js";

// Same inputs and constants as contracts/test/Vectors.t.sol. If either side changes, both tests fail.
const terms: Terms = {
  seller: "0x1111111111111111111111111111111111111111",
  buyer: "0x2222222222222222222222222222222222222222",
  token: "0x3333333333333333333333333333333333333333",
  faceAmount: 10_000_000_000n,
  dueDate: 1_800_000_000n,
  invoiceHash: keccak256(toBytes("vector-invoice")),
  advanceBps: 9000,
  feeAnnualBps: 800,
  lateAnnualBps: 1800,
  bondBps: 200,
  protocolFeeBps: 10,
  graceSeconds: 259_200n,
  defaultSeconds: 2_592_000n,
  pool: "0x4444444444444444444444444444444444444444",
  protocolTreasury: "0x5555555555555555555555555555555555555555",
};
const REGISTRY: Address = "0x7777777777777777777777777777777777777777";

describe("cross-language vectors (Solidity is the source of truth)", () => {
  it("hashTerms matches HundiLib.hashTerms", () => {
    expect(hashTerms(terms)).toBe("0x7ccba115c1eb1a4076e584ef91f3f88a76a5c45d320f03f44f5a521218e435ec");
  });

  it("invoiceKey matches HundiLib.invoiceKey", () => {
    expect(invoiceKey(terms.seller, terms.buyer, invoiceNumberHash("INV-VECTOR-1"))).toBe(
      "0xe9296aec573dd3985831885224c3aa12d561a822886af9a0c91ba6b4f8f76b69",
    );
  });

  it("EIP-712 acceptance digest matches AcceptanceRegistry.digest on chain 133", () => {
    const a: Acceptance = {
      buyer: terms.buyer,
      seller: terms.seller,
      token: terms.token,
      faceAmount: terms.faceAmount,
      dueDate: terms.dueDate,
      invoiceHash: terms.invoiceHash,
      invoiceNumberHash: invoiceNumberHash("INV-VECTOR-1"),
      termsHash: hashTerms(terms),
      vault: "0x6666666666666666666666666666666666666666",
      nonce: 1n,
      expiry: 1_790_604_800n,
    };
    expect(acceptanceDigest(a, 133, REGISTRY)).toBe(
      "0x8f90a5dfabcaf815366f431885044d97b4ee870b86a014c598b3bd930aae3037",
    );
  });
});
