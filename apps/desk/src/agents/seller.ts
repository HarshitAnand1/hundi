import { keccak256, toBytes, type Address, type Hex, type LocalAccount } from "viem";
import { deliveryDigest, invoiceHash, zInvoice, type InvoiceInput, type VerifyInvoiceInput } from "@hundi/sdk";

export interface IssueOptions {
  invoiceNumber: string;
  buyer: { address: Address; name: string };
  token: Address;
  amount: bigint;
  issuedAt: number;
  dueDate: number;
  poReference: string;
  goods: string;
  /** Defaults to the seller's own address. A different value is what a BEC attacker would send. */
  payTo?: Address;
  notes?: string;
}

/** Seller agent (A2A merchant role): issues and signs a canonical invoice. */
export class SellerAgent {
  constructor(readonly account: LocalAccount, readonly name: string) {}

  invoice(o: IssueOptions): InvoiceInput {
    return {
      version: "hundi.invoice.v1",
      invoiceNumber: o.invoiceNumber,
      issuedAt: o.issuedAt,
      dueDate: o.dueDate,
      seller: { address: this.account.address, name: this.name },
      buyer: o.buyer,
      token: o.token,
      amount: o.amount.toString(),
      currency: "USD",
      poReference: o.poReference,
      goodsHash: goodsHash(o.goods),
      payTo: o.payTo ?? this.account.address,
      ...(o.notes !== undefined ? { notes: o.notes } : {}),
    };
  }

  /** EIP-191 signature over the canonical invoice hash. */
  async sign(inv: InvoiceInput): Promise<Hex> {
    return this.account.signMessage({ message: { raw: invoiceHash(zInvoice.parse(inv)) } });
  }
}

export const goodsHash = (description: string): Hex => keccak256(toBytes(description));

/** Simulated logistics agent. Honest limit: a signed attestation from a trusted key, not a real carrier feed. */
export class LogisticsAgent {
  constructor(readonly account: LocalAccount) {}

  async attest(inv: InvoiceInput): Promise<NonNullable<VerifyInvoiceInput["delivery"]>> {
    const signature = await this.account.signMessage({ message: { raw: deliveryDigest(zInvoice.parse(inv)) } });
    return { attester: this.account.address, signature };
  }
}
