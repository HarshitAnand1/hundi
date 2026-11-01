import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { concat, keccak256, toHex, type Address, type Hex } from "viem";
import { privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts";
import { z } from "zod";
import { zAddress } from "@hundi/sdk";

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");

/** Shape written by contracts/script/Deploy.s.sol. */
export const zDeployment = z.object({
  chainId: z.number().int(),
  deployedAtBlock: z.number().int(),
  token: zAddress,
  tokenIsMock: z.boolean(),
  acceptanceRegistry: zAddress,
  receivableFactory: zAddress,
  vaultImplementation: zAddress,
  liquidityPool: zAddress,
  guardian: zAddress,
  underwriter: zAddress,
});
export type Deployment = z.infer<typeof zDeployment>;

export function loadDeployment(chainId: number): Deployment {
  const path = join(REPO_ROOT, "contracts/deployments", `${chainId}.json`);
  return zDeployment.parse(JSON.parse(readFileSync(path, "utf8")));
}

export interface DeskEnv {
  rpcUrl: string;
  /** If set, the RPC's chain id must match it. */
  expectedChainId?: number;
  operatorKey: Hex;
  hspMode: "self-relay" | "gateway";
  /** Face amount per demo invoice, token base units. */
  face: bigint;
}

/** Reads env without ever logging secret values. */
export function loadEnv(env: NodeJS.ProcessEnv = process.env): DeskEnv {
  const rpcUrl = env.RPC_URL ?? env.HSK_TESTNET_RPC_URL;
  if (!rpcUrl) throw new Error("RPC_URL (or HSK_TESTNET_RPC_URL) is not set");
  const key = env.DEPLOYER_PRIVATE_KEY;
  if (!key || !/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("DEPLOYER_PRIVATE_KEY is missing or malformed (value not shown)");
  const mode = env.HSP_MODE ?? "self-relay";
  if (mode !== "self-relay" && mode !== "gateway") throw new Error(`HSP_MODE must be self-relay or gateway`);
  return {
    rpcUrl,
    ...(env.HSK_CHAIN_ID ? { expectedChainId: Number(env.HSK_CHAIN_ID) } : {}),
    operatorKey: key as Hex,
    hspMode: mode,
    face: BigInt(env.DEMO_FACE ?? "10000000000"),
  };
}

export interface Roles {
  /** Burner deployer: liquidity provider, underwriter, keeper and desk relayer in the demo. */
  operator: PrivateKeyAccount;
  /** Buyer's agent wallet (signs acceptance, pays at maturity). */
  buyer: PrivateKeyAccount;
  /** Seller's agent wallet (signs invoices, receives the advance). */
  seller: PrivateKeyAccount;
  /** Simulated logistics agent that attests delivery (honest limit: not a real carrier). */
  logistics: PrivateKeyAccount;
  /** Desk's merchant-of-record key that signs self-relay carts. */
  merchant: PrivateKeyAccount;
  /** Address used to demonstrate payee-swap attacks. */
  attacker: PrivateKeyAccount;
  treasury: Address;
}

/**
 * Demo role keys are derived from the operator key, so whoever holds the burner can recover every
 * role wallet (and any funds sent to it). Never reuse a real key here.
 */
export function deriveRoles(operatorKey: Hex): Roles {
  const derive = (label: string) => privateKeyToAccount(keccak256(concat([operatorKey, toHex(`hundi.role:${label}`)])));
  return {
    operator: privateKeyToAccount(operatorKey),
    buyer: derive("buyer"),
    seller: derive("seller"),
    logistics: derive("logistics"),
    merchant: derive("merchant"),
    attacker: derive("attacker"),
    treasury: derive("treasury").address,
  };
}
