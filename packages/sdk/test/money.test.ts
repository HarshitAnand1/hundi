import { describe, expect, it } from "vitest";
import { advanceOf, bondOf, protocolFeeOf, waterfall, lenderDueAt, canonicalJson, type Terms } from "../src/index.js";

const USDC = 1_000_000n;
const DAY = 86_400n;
const fundedAt = 1_790_000_000n;
const t: Terms = {
  seller: "0x1111111111111111111111111111111111111111",
  buyer: "0x2222222222222222222222222222222222222222",
  token: "0x3333333333333333333333333333333333333333",
  faceAmount: 10_000n * USDC,
  dueDate: fundedAt + 73n * DAY,
  invoiceHash: `0x${"ab".repeat(32)}`,
  advanceBps: 9000,
  feeAnnualBps: 800,
  lateAnnualBps: 1800,
  bondBps: 200,
  protocolFeeBps: 10,
  graceSeconds: 3n * DAY,
  defaultSeconds: 30n * DAY,
  pool: "0x4444444444444444444444444444444444444444",
  protocolTreasury: "0x5555555555555555555555555555555555555555",
};

describe("money maths mirrors ReceivableVault (HANDOFF 5.4 worked example)", () => {
  it("reproduces every line of the worked example", () => {
    const w = waterfall(t, fundedAt, t.dueDate);
    expect(advanceOf(t)).toBe(9_000n * USDC);
    expect(bondOf(t)).toBe(180n * USDC);
    expect(w.sellerAtFunding).toBe(8_820n * USDC);
    expect(w.lenderDue).toBe(9_144n * USDC);
    expect(protocolFeeOf(t)).toBe(10n * USDC);
    expect(w.sellerResidual).toBe(846n * USDC);
    expect(w.sellerTotal).toBe(9_846n * USDC);
    expect(w.costToSeller).toBe(154n * USDC);
    expect(w.sellerTotal + 144n * USDC + w.protocolFee).toBe(t.faceAmount);
  });

  it("late interest starts after grace and matches the contract test", () => {
    expect(lenderDueAt(t, fundedAt, t.dueDate + t.graceSeconds)).toBe(9_144n * USDC);
    const late = (9_000n * USDC * 1800n * 10n * DAY) / (10_000n * 365n * DAY);
    expect(lenderDueAt(t, fundedAt, t.dueDate + t.graceSeconds + 10n * DAY)).toBe(9_144n * USDC + late);
  });

  it("partial payment pays only the lender and returns no bond", () => {
    const w = waterfall(t, fundedAt, t.dueDate, 5_000n * USDC);
    expect(w.sellerResidual).toBe(0n);
    expect(w.sellerTotal).toBe(8_820n * USDC);
  });
});

describe("canonicalJson", () => {
  it("is key-order independent and stringifies bigint", () => {
    expect(canonicalJson({ b: 1, a: { d: 2n, c: "x" } })).toBe('{"a":{"c":"x","d":"2"},"b":1}');
    expect(canonicalJson({ a: 1, b: 2 })).toBe(canonicalJson({ b: 2, a: 1 }));
  });
  it("drops undefined and rejects floats", () => {
    expect(canonicalJson({ a: undefined, b: 1 })).toBe('{"b":1}');
    expect(() => canonicalJson({ a: 1.5 })).toThrow();
  });
});
