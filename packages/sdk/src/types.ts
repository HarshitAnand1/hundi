import { z } from "zod";
import { getAddress, isAddress, type Address, type Hex } from "viem";

/** Checksummed EVM address. */
export const zAddress = z
  .string()
  .refine((s) => isAddress(s, { strict: false }), "invalid address")
  .transform((s) => getAddress(s) as Address);

export const zHex32 = z
  .string()
  .regex(/^0x[0-9a-fA-F]{64}$/, "expected 32-byte hex")
  .transform((s) => s.toLowerCase() as Hex);

export const zHex = z
  .string()
  .regex(/^0x([0-9a-fA-F]{2})*$/, "expected hex bytes")
  .transform((s) => s.toLowerCase() as Hex);

/** Token base units as a decimal string (JSON-safe), parsed to bigint. */
export const zAmount = z
  .string()
  .regex(/^(0|[1-9][0-9]*)$/, "expected base-unit integer string")
  .transform((s) => BigInt(s));

/** Unix seconds. */
export const zUnix = z.number().int().nonnegative();

/**
 * Canonical invoice issued by the seller agent (HANDOFF 5.2 step 1).
 * Everything here is counterparty data: untrusted, never placed in an LLM instruction position.
 */
export const zInvoice = z
  .object({
    version: z.literal("hundi.invoice.v1"),
    invoiceNumber: z.string().min(1).max(64),
    issuedAt: zUnix,
    dueDate: zUnix,
    seller: z.object({ address: zAddress, name: z.string().max(200) }).strict(),
    buyer: z.object({ address: zAddress, name: z.string().max(200) }).strict(),
    token: zAddress,
    amount: zAmount,
    currency: z.literal("USD"),
    poReference: z.string().min(1).max(64),
    goodsHash: zHex32,
    payTo: zAddress,
    notes: z.string().max(2000).optional(),
  })
  .strict();
export type Invoice = z.output<typeof zInvoice>;
export type InvoiceInput = z.input<typeof zInvoice>;

/** Mirrors contracts/src/Types.sol `Terms` (FROZEN 2026-11-01). Field order matters for hashing. */
export interface Terms {
  seller: Address;
  buyer: Address;
  token: Address;
  faceAmount: bigint;
  dueDate: bigint; // uint64
  invoiceHash: Hex;
  advanceBps: number; // uint16
  feeAnnualBps: number;
  lateAnnualBps: number;
  bondBps: number;
  protocolFeeBps: number;
  graceSeconds: bigint; // uint64
  defaultSeconds: bigint;
  pool: Address;
  protocolTreasury: Address;
}

/** Mirrors contracts/src/Types.sol `Acceptance` (FROZEN 2026-11-01). */
export interface Acceptance {
  buyer: Address;
  seller: Address;
  token: Address;
  faceAmount: bigint;
  dueDate: bigint;
  invoiceHash: Hex;
  invoiceNumberHash: Hex;
  termsHash: Hex;
  vault: Address;
  nonce: bigint;
  expiry: bigint;
}

export type VaultState = "Open" | "Funded" | "Settled" | "Defaulted" | "Cancelled";
export const VAULT_STATES: readonly VaultState[] = ["Open", "Funded", "Settled", "Defaulted", "Cancelled"];

export interface Refusal<C extends string> {
  code: C;
  detail: string;
}
