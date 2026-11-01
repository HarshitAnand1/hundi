import { encodePacked, keccak256, toBytes, verifyMessage, type Address, type Hex } from "viem";
import { zInvoice, zHex, type Invoice, type Refusal } from "./types.js";
import { invoiceHash, invoiceKey, invoiceNumberHash } from "./terms.js";

/** HANDOFF Section 8. Every code is returned to the caller and covered by a test. */
export const INVOICE_REFUSAL_CODES = [
  "SCHEMA_INVALID",
  "SIGNATURE_INVALID",
  "VENDOR_NOT_ALLOWED",
  "OVER_CAP",
  "DUPLICATE_INVOICE",
  "PO_MISMATCH",
  "DELIVERY_NOT_ATTESTED",
  "DUE_DATE_OUT_OF_POLICY",
  "TOKEN_MISMATCH",
  "PAYEE_CHANGED",
  "HUMAN_APPROVAL_REQUIRED",
  "LLM_RISK_FLAG",
] as const;
export type InvoiceRefusalCode = (typeof INVOICE_REFUSAL_CODES)[number];

export interface BuyerPolicy {
  /** The buyer this agent acts for. */
  buyer: Address;
  /** Settlement token (USDC.e) from config. */
  token: Address;
  perInvoiceCap: bigint;
  /** Amounts at or above this need an explicit human approval. */
  humanApprovalThreshold: bigint;
  minTenorSeconds: number;
  maxTenorSeconds: number;
  /** Keys trusted to sign delivery attestations (simulated logistics agent in the prototype). */
  trustedAttesters: readonly Address[];
}

export interface VendorRecord {
  address: Address;
  /** Payout address on file. A different payTo on the invoice is a payee change (BEC). */
  payTo: Address;
  capPerInvoice?: bigint;
}

export interface PurchaseOrder {
  poReference: string;
  buyer: Address;
  seller: Address;
  /** Maximum invoiceable amount, token base units. */
  amount: bigint;
  goodsHash: Hex;
}

export interface DeliveryAttestation {
  attester: Address;
  /** EIP-191 signature over deliveryDigest(invoice). */
  signature: Hex;
}

/** Output of an LLM risk pass. It can only add a refusal; it can never approve. */
export interface LlmRiskSignal {
  flagged: boolean;
  reason?: string;
}

export interface VerifyInvoiceInput {
  /** Untrusted JSON from the seller agent. */
  invoice: unknown;
  /** Seller's EIP-191 signature over invoiceHash. */
  sellerSignature: unknown;
  delivery?: DeliveryAttestation;
  llm?: LlmRiskSignal;
  humanApproved?: boolean;
}

export interface VerifyInvoiceDeps {
  policy: BuyerPolicy;
  /** Unix seconds. */
  now: number;
  getVendor(address: Address): VendorRecord | undefined | Promise<VendorRecord | undefined>;
  getPurchaseOrder(poReference: string): PurchaseOrder | undefined | Promise<PurchaseOrder | undefined>;
  /** True if this invoiceKey was already accepted (local DB and/or AcceptanceRegistry.invoiceKeyUsed). */
  isInvoiceKeyUsed(key: Hex): boolean | Promise<boolean>;
}

export type VerifyInvoiceResult =
  | { ok: true; invoice: Invoice; invoiceHash: Hex; invoiceNumberHash: Hex; invoiceKey: Hex }
  | { ok: false; refusals: Refusal<InvoiceRefusalCode>[] };

/** What a delivery attester signs: binds the invoice, PO and goods. */
export function deliveryDigest(inv: Invoice): Hex {
  return keccak256(
    encodePacked(
      ["string", "bytes32", "bytes32", "bytes32"],
      ["hundi.delivery.v1", invoiceHash(inv), keccak256(toBytes(inv.poReference)), inv.goodsHash],
    ),
  );
}

async function sigValid(signer: Address, digest: Hex, sig: Hex): Promise<boolean> {
  try {
    return await verifyMessage({ address: signer, message: { raw: digest }, signature: sig });
  } catch {
    return false;
  }
}

/**
 * Deterministic acceptance gate (HANDOFF 5.2 step 3, Section 8). Fails closed: any exception,
 * missing dependency answer or LLM flag is a refusal. Returns every applicable refusal, in code order.
 */
export async function verifyInvoice(input: VerifyInvoiceInput, deps: VerifyInvoiceDeps): Promise<VerifyInvoiceResult> {
  const parsed = zInvoice.safeParse(input.invoice);
  const sigParsed = zHex.safeParse(input.sellerSignature);
  if (!parsed.success || !sigParsed.success) {
    const detail = !parsed.success
      ? parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")
      : "sellerSignature: not hex";
    return { ok: false, refusals: [{ code: "SCHEMA_INVALID", detail }] };
  }
  const inv = parsed.data;
  const { policy, now } = deps;
  const refusals: Refusal<InvoiceRefusalCode>[] = [];
  const refuse = (code: InvoiceRefusalCode, detail: string) => refusals.push({ code, detail });

  const hash = invoiceHash(inv);
  const numberHash = invoiceNumberHash(inv.invoiceNumber);
  const key = invoiceKey(inv.seller.address, inv.buyer.address, numberHash);

  try {
    if (!(await sigValid(inv.seller.address, hash, sigParsed.data))) {
      refuse("SIGNATURE_INVALID", "seller signature does not match invoiceHash");
    }

    const vendor = await deps.getVendor(inv.seller.address);
    if (!vendor) refuse("VENDOR_NOT_ALLOWED", `seller ${inv.seller.address} is not an approved vendor`);

    const cap = vendor?.capPerInvoice !== undefined && vendor.capPerInvoice < policy.perInvoiceCap
      ? vendor.capPerInvoice
      : policy.perInvoiceCap;
    if (inv.amount > cap) refuse("OVER_CAP", `amount ${inv.amount} exceeds cap ${cap}`);

    if (await deps.isInvoiceKeyUsed(key)) refuse("DUPLICATE_INVOICE", `invoice ${inv.invoiceNumber} already accepted`);

    const po = await deps.getPurchaseOrder(inv.poReference);
    if (!po) {
      refuse("PO_MISMATCH", `no purchase order ${inv.poReference}`);
    } else {
      const issues: string[] = [];
      if (inv.buyer.address !== policy.buyer || po.buyer !== policy.buyer) issues.push("buyer");
      if (po.seller !== inv.seller.address) issues.push("seller");
      if (inv.amount > po.amount) issues.push(`amount ${inv.amount} > PO ${po.amount}`);
      if (po.goodsHash.toLowerCase() !== inv.goodsHash) issues.push("goodsHash");
      if (issues.length) refuse("PO_MISMATCH", `PO ${inv.poReference}: ${issues.join(", ")}`);
    }

    const d = input.delivery;
    const attested =
      d !== undefined &&
      policy.trustedAttesters.some((a) => a.toLowerCase() === d.attester.toLowerCase()) &&
      (await sigValid(d.attester, deliveryDigest(inv), d.signature));
    if (!attested) refuse("DELIVERY_NOT_ATTESTED", "no valid delivery attestation from a trusted attester");

    const tenor = inv.dueDate - now;
    if (inv.dueDate <= inv.issuedAt || tenor < policy.minTenorSeconds || tenor > policy.maxTenorSeconds) {
      refuse("DUE_DATE_OUT_OF_POLICY", `tenor ${tenor}s outside [${policy.minTenorSeconds}, ${policy.maxTenorSeconds}]`);
    }

    if (inv.token !== policy.token) refuse("TOKEN_MISMATCH", `token ${inv.token} is not ${policy.token}`);

    if (inv.payTo !== inv.seller.address || (vendor && vendor.payTo !== inv.payTo)) {
      refuse("PAYEE_CHANGED", `payTo ${inv.payTo} differs from the vendor's address on file`);
    }

    if (inv.amount >= policy.humanApprovalThreshold && input.humanApproved !== true) {
      refuse("HUMAN_APPROVAL_REQUIRED", `amount ${inv.amount} >= threshold ${policy.humanApprovalThreshold}`);
    }

    if (input.llm?.flagged) refuse("LLM_RISK_FLAG", input.llm.reason ?? "risk flagged by model");
  } catch (err) {
    // Fail closed: a dependency error is never an approval.
    refuse("SCHEMA_INVALID", `verification error: ${err instanceof Error ? err.message : String(err)}`);
  }

  if (refusals.length) {
    const order = (c: InvoiceRefusalCode) => INVOICE_REFUSAL_CODES.indexOf(c);
    return { ok: false, refusals: refusals.sort((a, b) => order(a.code) - order(b.code)) };
  }
  return { ok: true, invoice: inv, invoiceHash: hash, invoiceNumberHash: numberHash, invoiceKey: key };
}
