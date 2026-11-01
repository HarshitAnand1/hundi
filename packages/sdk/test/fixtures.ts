import { keccak256, toBytes, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  deliveryDigest,
  invoiceHash,
  zInvoice,
  type BuyerPolicy,
  type InvoiceInput,
  type PurchaseOrder,
  type VendorRecord,
  type VerifyInvoiceDeps,
  type VerifyInvoiceInput,
} from "../src/index.js";

// Deterministic throwaway test keys (keccak of a label). Never use these anywhere real.
const key = (label: string) => keccak256(toBytes(`hundi-test-key:${label}`));
export const sellerAcct = privateKeyToAccount(key("seller"));
export const buyerAcct = privateKeyToAccount(key("buyer"));
export const attesterAcct = privateKeyToAccount(key("logistics"));
export const merchantAcct = privateKeyToAccount(key("merchant"));
export const strangerAcct = privateKeyToAccount(key("stranger"));

export const USDC = 1_000_000n;
export const NOW = 1_790_000_000;
export const DAY = 86_400;
export const TOKEN = "0x3333333333333333333333333333333333333333" as const;

export const goodsHash: Hex = keccak256(toBytes("40 cartons, cotton yarn, lot 7"));

export function baseInvoice(over: Partial<InvoiceInput> = {}): InvoiceInput {
  return {
    version: "hundi.invoice.v1",
    invoiceNumber: "INV-2026-001",
    issuedAt: NOW,
    dueDate: NOW + 73 * DAY,
    seller: { address: sellerAcct.address, name: "Surat Textiles Pvt Ltd" },
    buyer: { address: buyerAcct.address, name: "Rotterdam Fabrics BV" },
    token: TOKEN,
    amount: (10_000n * USDC).toString(),
    currency: "USD",
    poReference: "PO-7781",
    goodsHash,
    payTo: sellerAcct.address,
    ...over,
  };
}

export const policy: BuyerPolicy = {
  buyer: buyerAcct.address,
  token: TOKEN,
  perInvoiceCap: 25_000n * USDC,
  humanApprovalThreshold: 20_000n * USDC,
  minTenorSeconds: 7 * DAY,
  maxTenorSeconds: 120 * DAY,
  trustedAttesters: [attesterAcct.address],
};

export const vendor: VendorRecord = { address: sellerAcct.address, payTo: sellerAcct.address };
export const po: PurchaseOrder = {
  poReference: "PO-7781",
  buyer: buyerAcct.address,
  seller: sellerAcct.address,
  amount: 10_000n * USDC,
  goodsHash,
};

export function deps(over: Partial<VerifyInvoiceDeps> = {}, usedKeys: Set<string> = new Set()): VerifyInvoiceDeps {
  return {
    policy,
    now: NOW,
    getVendor: (a) => (a === vendor.address ? vendor : undefined),
    getPurchaseOrder: (ref) => (ref === po.poReference ? po : undefined),
    isInvoiceKeyUsed: (k) => usedKeys.has(k),
    ...over,
  };
}

/** Seller-signed invoice with a valid delivery attestation. */
export async function signedInput(
  inv: InvoiceInput,
  opts: { signer?: typeof sellerAcct; attester?: typeof attesterAcct } = {},
): Promise<VerifyInvoiceInput> {
  const parsed = zInvoice.parse(inv);
  const signer = opts.signer ?? sellerAcct;
  const attester = opts.attester ?? attesterAcct;
  return {
    invoice: inv,
    sellerSignature: await signer.signMessage({ message: { raw: invoiceHash(parsed) } }),
    delivery: {
      attester: attester.address,
      signature: await attester.signMessage({ message: { raw: deliveryDigest(parsed) } }),
    },
  };
}
