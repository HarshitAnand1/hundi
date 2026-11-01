import type { Address, Hash, Hex, LocalAccount } from "viem";
import { advanceOf, bondOf, liquidityPoolAbi, protocolFeeOf, waterfall, type Acceptance, type Invoice, type Terms } from "@hundi/sdk";
import type { Chainish } from "../chain.js";

/** Pricing inside the pool's on-chain bounds. Deterministic: an LLM may only explain these numbers. */
export const DEFAULT_PRICING = {
  advanceBps: 9000,
  feeAnnualBps: 800,
  lateAnnualBps: 1800,
  bondBps: 200,
  protocolFeeBps: 10,
  graceSeconds: 3n * 86_400n,
  defaultSeconds: 30n * 86_400n,
} as const;

export class Underwriter {
  constructor(readonly account: LocalAccount, private readonly c: Chainish, private readonly treasury: Address) {}

  terms(inv: Invoice, invoiceHash: Hex): Terms {
    return {
      seller: inv.seller.address,
      buyer: inv.buyer.address,
      token: inv.token,
      faceAmount: inv.amount,
      dueDate: BigInt(inv.dueDate),
      invoiceHash,
      ...DEFAULT_PRICING,
      pool: this.c.deployment.liquidityPool,
      protocolTreasury: this.treasury,
    };
  }

  /** Plain-language memo generated from the numbers (template, not a model). */
  memo(t: Terms, now: bigint): string {
    const w = waterfall(t, now, t.dueDate);
    const usd = (x: bigint) => (Number(x) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 2 });
    return [
      `Advance ${usd(advanceOf(t))} (${t.advanceBps / 100}% of ${usd(t.faceAmount)}), bond ${usd(bondOf(t))} held in the vault.`,
      `Seller receives ${usd(w.sellerAtFunding)} now and ${usd(w.sellerResidual + w.bond)} at maturity; total cost ${usd(w.costToSeller)}.`,
      `Lender due ${usd(w.lenderDue)} at maturity (${t.feeAnnualBps / 100}% p.a.), protocol ${usd(protocolFeeOf(t))}.`,
    ].join(" ");
  }

  /** Registers the acceptance, creates the vault and funds it in one call. */
  async advance(t: Terms, a: Acceptance, sig: Hex): Promise<Hash> {
    const w = this.c.wallet(this.account);
    const { request } = await this.c.pub.simulateContract({
      account: this.account,
      address: this.c.deployment.liquidityPool,
      abi: liquidityPoolAbi,
      functionName: "advance",
      args: [t, a, sig],
    });
    return this.c.confirm(await w.writeContract(request));
  }
}
