import type { Address, Hex } from "viem";
import { hashTerms, receivableVaultAbi, zInvoice, type PurchaseOrder, type VendorRecord, type VerifyInvoiceInput } from "@hundi/sdk";
import {
  BuyerAgent,
  Desk,
  Keeper,
  LogisticsAgent,
  SellerAgent,
  Store,
  Underwriter,
  goodsHash,
  prepareFunds,
  reads,
  type Chainish,
  type Roles,
} from "@hundi/desk";

const DAY = 86_400;
const USDC = 1_000_000n;

interface Pending {
  input: VerifyInvoiceInput;
  invoiceNumber: string;
}

/**
 * The six Hundi tools behind the MCP server. Every approval is a deterministic check from @hundi/sdk;
 * a calling agent (or model) can request actions but cannot make a refused invoice pass.
 * Demo scope: the seller, buyer, logistics and lender roles are the desk's derived demo wallets, and the
 * buyer's purchase-order book is simulated (issue_invoice registers the PO).
 */
export class HundiTools {
  private readonly pending = new Map<string, Pending>();
  private readonly orders = new Map<string, PurchaseOrder>();
  private readonly buyer: BuyerAgent;
  private readonly seller: SellerAgent;
  private readonly logistics: LogisticsAgent;
  private readonly underwriter: Underwriter;
  private readonly keeper: Keeper;
  private readonly desk: Desk;

  constructor(private readonly c: Chainish, private readonly roles: Roles, readonly store: Store = new Store(c.chain.id)) {
    const vendors = new Map<string, VendorRecord>([[roles.seller.address.toLowerCase(), { address: roles.seller.address, payTo: roles.seller.address }]]);
    this.buyer = new BuyerAgent(
      roles.buyer,
      c,
      store,
      {
        buyer: roles.buyer.address,
        token: c.deployment.token,
        perInvoiceCap: 50_000n * USDC,
        humanApprovalThreshold: 20_000n * USDC,
        minTenorSeconds: 7 * DAY,
        maxTenorSeconds: 120 * DAY,
        trustedAttesters: [roles.logistics.address],
      },
      vendors,
      this.orders,
      roles.merchant.address,
    );
    this.seller = new SellerAgent(roles.seller, "Surat Textiles Pvt Ltd");
    this.logistics = new LogisticsAgent(roles.logistics);
    this.underwriter = new Underwriter(roles.operator, c, roles.treasury);
    this.keeper = new Keeper(roles.operator, c);
    this.desk = new Desk(roles.merchant);
  }

  private async now(): Promise<number> {
    return Number((await this.c.pub.getBlock()).timestamp);
  }

  async issueInvoice(a: { invoiceNumber: string; amount: bigint; dueInDays: number; goods: string; poAmount?: bigint; payTo?: Address; notes?: string }) {
    const now = await this.now();
    const poReference = `PO-${a.invoiceNumber}`;
    this.orders.set(poReference, {
      poReference,
      buyer: this.roles.buyer.address,
      seller: this.roles.seller.address,
      amount: a.poAmount ?? a.amount,
      goodsHash: goodsHash(a.goods),
    });
    const invoice = this.seller.invoice({
      invoiceNumber: a.invoiceNumber,
      buyer: { address: this.roles.buyer.address, name: "Rotterdam Fabrics BV" },
      token: this.c.deployment.token,
      amount: a.amount,
      issuedAt: now,
      dueDate: now + a.dueInDays * DAY,
      poReference,
      goods: a.goods,
      ...(a.payTo ? { payTo: a.payTo } : {}),
      ...(a.notes !== undefined ? { notes: a.notes } : {}),
    });
    const input = { invoice, sellerSignature: await this.seller.sign(invoice), delivery: await this.logistics.attest(invoice) };
    this.pending.set(a.invoiceNumber, { input, invoiceNumber: a.invoiceNumber });
    this.store.log({ kind: "invoice.issued", summary: `${a.invoiceNumber} for ${a.amount} issued via MCP` });
    return { invoice, sellerSignature: input.sellerSignature, delivery: input.delivery };
  }

  /** Runs verifyInvoice; on pass, prices the terms and signs the EIP-712 acceptance (off-chain). */
  async acceptInvoice(a: { invoiceNumber: string; humanApproved?: boolean }) {
    const p = this.pending.get(a.invoiceNumber);
    if (!p) return { ok: false as const, error: `unknown invoice ${a.invoiceNumber}; call issue_invoice first` };
    const now = await this.now();
    const review = await this.buyer.review({ ...p.input, ...(a.humanApproved !== undefined ? { humanApproved: a.humanApproved } : {}) }, now);
    if (!review.ok) {
      this.store.log({ kind: "invoice.refused", summary: `${a.invoiceNumber}: ${review.refusals.map((r) => r.code).join(", ")}` });
      return { ok: false as const, refusals: review.refusals };
    }
    const terms = this.underwriter.terms(review.invoice, review.invoiceHash);
    const termsHash = hashTerms(terms);
    const { acceptance, signature } = await this.buyer.accept(terms, termsHash, a.invoiceNumber, now);
    this.accepted.set(termsHash.toLowerCase(), { terms, acceptance, signature, invoice: review.invoice });
    this.store.log({ kind: "invoice.accepted", termsHash, summary: `Buyer agent signed acceptance; vault ${acceptance.vault}` });
    return { ok: true as const, termsHash, vault: acceptance.vault, terms, memo: this.underwriter.memo(terms, BigInt(now)) };
  }

  private readonly accepted = new Map<
    string,
    { terms: ReturnType<Underwriter["terms"]>; acceptance: Awaited<ReturnType<BuyerAgent["accept"]>>["acceptance"]; signature: Hex; invoice: ReturnType<typeof zInvoice.parse> }
  >();

  /** Pool advance: records the acceptance on-chain, creates the vault at its predicted address and funds the seller. */
  async requestAdvance(a: { termsHash: Hex }) {
    const x = this.accepted.get(a.termsHash.toLowerCase());
    if (!x) return { ok: false as const, error: "no signed acceptance for this termsHash; call accept_invoice first" };
    const txs = await prepareFunds(this.c, this.roles, x.terms.faceAmount, this.store);
    const tx = await this.underwriter.advance(x.terms, x.acceptance, x.signature);
    this.store.put({ termsHash: x.acceptance.termsHash, invoice: x.invoice, terms: x.terms, acceptance: x.acceptance, vault: x.acceptance.vault, txs: { advance: tx } });
    this.store.log({ kind: "advance.funded", termsHash: x.acceptance.termsHash, summary: `Pool advanced; vault ${x.acceptance.vault} funded`, tx });
    return { ok: true as const, vault: x.acceptance.vault, advanceTx: tx, fundingTxs: txs };
  }

  /** Desk creates the order, the buyer agent runs verifyCart, pays the vault, and the keeper settles. */
  async payInvoice(a: { termsHash: Hex }) {
    const rec = this.store.getByTermsHash(a.termsHash);
    if (!rec) return { ok: false as const, error: "unknown receivable" };
    const cart = await this.desk.order(rec, `ord-${Date.now()}`);
    const paid = await this.buyer.pay(cart);
    if (!paid.ok) return { ok: false as const, refusals: paid.result.ok ? [] : paid.result.refusals };
    this.store.log({ kind: "payment.sent", termsHash: rec.termsHash, summary: "Buyer paid vault (self-relay)", tx: paid.tx });
    const { tx, settled } = await this.keeper.settle(rec.vault);
    this.store.put({ ...rec, txs: { ...rec.txs, pay: paid.tx, settle: tx } });
    this.store.log({ kind: "vault.settled", termsHash: rec.termsHash, tx, summary: "Waterfall settled", ...(settled ? { data: { ...settled } } : {}) });
    return { ok: true as const, payTx: paid.tx, settleTx: tx, settled };
  }

  async getReceivable(a: { termsHash: Hex }) {
    const rec = this.store.getByTermsHash(a.termsHash);
    if (!rec) return { ok: false as const, error: "unknown receivable" };
    const r = reads(this.c);
    const read = (functionName: "lenderPaid" | "protocolPaid" | "sellerPaid" | "bondHeld") =>
      this.c.pub.readContract({ address: rec.vault, abi: receivableVaultAbi, functionName });
    return {
      ok: true as const,
      invoiceNumber: rec.invoice.invoiceNumber,
      vault: rec.vault,
      state: await r.vaultState(rec.vault),
      faceAmount: rec.terms.faceAmount,
      dueDate: rec.terms.dueDate,
      lenderPaid: await read("lenderPaid"),
      protocolPaid: await read("protocolPaid"),
      sellerPaid: await read("sellerPaid"),
      bondHeld: await read("bondHeld"),
      txs: rec.txs,
    };
  }

  listReceivables() {
    return this.store.receivables.map((r) => ({ termsHash: r.termsHash, invoiceNumber: r.invoice.invoiceNumber, vault: r.vault, faceAmount: r.terms.faceAmount }));
  }
}
