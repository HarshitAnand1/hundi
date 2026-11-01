import { parseEventLogs, type Address, type Hash, type LocalAccount } from "viem";
import { receivableVaultAbi } from "@hundi/sdk";
import type { Chainish } from "../chain.js";

export interface SettledAmounts {
  lenderPaid: bigint;
  protocolPaid: bigint;
  sellerPaid: bigint;
  daysLate: bigint;
}

/** Keeper: every function it calls is permissionless; anyone could run it. */
export class Keeper {
  constructor(readonly account: LocalAccount, private readonly c: Chainish) {}

  async settle(vault: Address): Promise<{ tx: Hash; settled?: SettledAmounts }> {
    const { request } = await this.c.pub.simulateContract({
      account: this.account,
      address: vault,
      abi: receivableVaultAbi,
      functionName: "settle",
    });
    const tx = await this.c.confirm(await this.c.wallet(this.account).writeContract(request));
    const receipt = await this.c.pub.getTransactionReceipt({ hash: tx });
    const ev = parseEventLogs({ abi: receivableVaultAbi, logs: receipt.logs, eventName: "Settled" })[0];
    return ev ? { tx, settled: ev.args as SettledAmounts } : { tx };
  }
}
