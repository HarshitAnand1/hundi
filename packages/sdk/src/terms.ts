import { encodeAbiParameters, keccak256, toBytes, type Address, type Hex } from "viem";
import { canonicalHash } from "./canonical.js";
import type { Invoice, Terms } from "./types.js";

/** ABI shape of `Terms`, in Solidity field order. */
export const TERMS_ABI_COMPONENTS = [
  { name: "seller", type: "address" },
  { name: "buyer", type: "address" },
  { name: "token", type: "address" },
  { name: "faceAmount", type: "uint256" },
  { name: "dueDate", type: "uint64" },
  { name: "invoiceHash", type: "bytes32" },
  { name: "advanceBps", type: "uint16" },
  { name: "feeAnnualBps", type: "uint16" },
  { name: "lateAnnualBps", type: "uint16" },
  { name: "bondBps", type: "uint16" },
  { name: "protocolFeeBps", type: "uint16" },
  { name: "graceSeconds", type: "uint64" },
  { name: "defaultSeconds", type: "uint64" },
  { name: "pool", type: "address" },
  { name: "protocolTreasury", type: "address" },
] as const;

/** keccak256(abi.encode(terms)) — equals HundiLib.hashTerms and the vault's CREATE2 salt. */
export function hashTerms(t: Terms): Hex {
  return keccak256(encodeAbiParameters([{ type: "tuple", components: TERMS_ABI_COMPONENTS }], [t]));
}

/** keccak256 of the canonical invoice JSON (parsed form, so address casing does not matter). */
export function invoiceHash(inv: Invoice): Hex {
  return canonicalHash(inv);
}

export function invoiceNumberHash(invoiceNumber: string): Hex {
  return keccak256(toBytes(invoiceNumber));
}

/** keccak256(abi.encode(seller, buyer, invoiceNumberHash)) — equals HundiLib.invoiceKey. */
export function invoiceKey(seller: Address, buyer: Address, numberHash: Hex): Hex {
  return keccak256(
    encodeAbiParameters([{ type: "address" }, { type: "address" }, { type: "bytes32" }], [seller, buyer, numberHash]),
  );
}

// ------------------------------------------------------------------ money (mirrors ReceivableVault)

const BPS = 10_000n;
const YEAR = 365n * 24n * 3600n;

export const interest = (principal: bigint, annualBps: number, seconds: bigint): bigint =>
  (principal * BigInt(annualBps) * seconds) / (BPS * YEAR);

export const advanceOf = (t: Terms): bigint => (t.faceAmount * BigInt(t.advanceBps)) / BPS;
export const bondOf = (t: Terms): bigint => (advanceOf(t) * BigInt(t.bondBps)) / BPS;
export const protocolFeeOf = (t: Terms): bigint => (t.faceAmount * BigInt(t.protocolFeeBps)) / BPS;

/** Lender due at `now` for a vault funded at `fundedAt` (advance + fee to due date + late interest after grace). */
export function lenderDueAt(t: Terms, fundedAt: bigint, now: bigint): bigint {
  const adv = advanceOf(t);
  const atMaturity = adv + interest(adv, t.feeAnnualBps, t.dueDate - fundedAt);
  const lateStart = t.dueDate + t.graceSeconds;
  return atMaturity + (now > lateStart ? interest(adv, t.lateAnnualBps, now - lateStart) : 0n);
}

export interface Waterfall {
  advance: bigint;
  bond: bigint;
  sellerAtFunding: bigint;
  lenderDue: bigint;
  protocolFee: bigint;
  sellerResidual: bigint;
  sellerTotal: bigint;
  costToSeller: bigint;
}

/** Full payout for a single on-time-or-late payment of `paid` at `now`. Used by the dashboard and underwriter. */
export function waterfall(t: Terms, fundedAt: bigint, now: bigint, paid: bigint = t.faceAmount): Waterfall {
  const advance = advanceOf(t);
  const bond = bondOf(t);
  const lenderDue = lenderDueAt(t, fundedAt, now);
  const protocolFee = protocolFeeOf(t);
  const toLender = paid < lenderDue ? paid : lenderDue;
  const rest = paid - toLender;
  const toProtocol = rest < protocolFee ? rest : protocolFee;
  const settled = toLender === lenderDue && toProtocol === protocolFee;
  const sellerResidual = rest - toProtocol;
  const sellerTotal = advance - bond + sellerResidual + (settled ? bond : 0n);
  return {
    advance,
    bond,
    sellerAtFunding: advance - bond,
    lenderDue,
    protocolFee,
    sellerResidual,
    sellerTotal,
    costToSeller: t.faceAmount - sellerTotal,
  };
}
