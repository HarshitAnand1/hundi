import {
  createPublicClient,
  createWalletClient,
  defineChain,
  erc20Abi,
  http,
  parseAbi,
  type Address,
  type Hash,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Account,
  type Transport,
} from "viem";
import {
  VAULT_STATES,
  acceptanceRegistryAbi,
  liquidityPoolAbi,
  receivableFactoryAbi,
  receivableVaultAbi,
  type Terms,
  type VaultState,
} from "@hundi/sdk";
import { loadDeployment, type Deployment } from "./config.js";

export const mockTokenAbi = parseAbi(["function mint(address to, uint256 amount)"]);

export interface Chainish {
  chain: Chain;
  pub: PublicClient<Transport, Chain>;
  deployment: Deployment;
  wallet(account: Account): WalletClient<Transport, Chain, Account>;
  /** Wait for a tx and throw if it reverted. */
  confirm(hash: Hash): Promise<Hash>;
}

export async function connect(rpcUrl: string, expectedChainId?: number): Promise<Chainish> {
  const probe = createPublicClient({ transport: http(rpcUrl) });
  const id = await probe.getChainId();
  if (expectedChainId !== undefined && id !== expectedChainId) {
    throw new Error(`RPC chain id ${id} does not match HSK_CHAIN_ID ${expectedChainId}`);
  }
  const chain = defineChain({
    id,
    name: `hsk-${id}`,
    nativeCurrency: { name: "HSK", symbol: "HSK", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  });
  const pub = createPublicClient({ chain, transport: http(rpcUrl) });
  const deployment = loadDeployment(id);
  return {
    chain,
    pub,
    deployment,
    wallet: (account) => createWalletClient({ account, chain, transport: http(rpcUrl) }),
    confirm: async (hash) => {
      const r = await pub.waitForTransactionReceipt({ hash });
      if (r.status !== "success") throw new Error(`tx ${hash} reverted`);
      return hash;
    },
  };
}

/** Typed chain reads used by the agents. */
export function reads(c: Chainish) {
  const d = c.deployment;
  return {
    balanceOf: (who: Address) => c.pub.readContract({ address: d.token, abi: erc20Abi, functionName: "balanceOf", args: [who] }),
    predictVault: (t: Terms) =>
      c.pub.readContract({ address: d.receivableFactory, abi: receivableFactoryAbi, functionName: "predictVault", args: [t] }),
    invoiceKeyUsed: (key: `0x${string}`) =>
      c.pub.readContract({ address: d.acceptanceRegistry, abi: acceptanceRegistryAbi, functionName: "invoiceKeyUsed", args: [key] }),
    nonceUsed: (buyer: Address, nonce: bigint) =>
      c.pub.readContract({ address: d.acceptanceRegistry, abi: acceptanceRegistryAbi, functionName: "nonceUsed", args: [buyer, nonce] }),
    isVault: (v: Address) =>
      c.pub.readContract({ address: d.receivableFactory, abi: receivableFactoryAbi, functionName: "isVault", args: [v] }),
    poolIdle: () => c.pub.readContract({ address: d.liquidityPool, abi: liquidityPoolAbi, functionName: "idle" }),
    async vaultState(v: Address): Promise<VaultState> {
      const code = await c.pub.getCode({ address: v });
      if (!code || code === "0x") return "Open"; // not deployed yet: a predicted, prepayable address
      const s = await c.pub.readContract({ address: v, abi: receivableVaultAbi, functionName: "state" });
      const state = VAULT_STATES[Number(s)];
      if (!state) throw new Error(`unknown vault state ${s}`);
      return state;
    },
  };
}
