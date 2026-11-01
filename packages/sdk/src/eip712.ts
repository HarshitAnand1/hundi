import {
  hashTypedData,
  recoverTypedDataAddress,
  type Address,
  type Hex,
  type LocalAccount,
  type TypedDataDomain,
} from "viem";
import type { Acceptance } from "./types.js";

/** Must match AcceptanceRegistry's constructor: EIP712("Hundi AcceptanceRegistry", "1"). */
export function acceptanceDomain(chainId: number, registry: Address): TypedDataDomain {
  return { name: "Hundi AcceptanceRegistry", version: "1", chainId, verifyingContract: registry };
}

/** Must match AcceptanceRegistry.ACCEPTANCE_TYPEHASH field-for-field. */
export const ACCEPTANCE_TYPES = {
  Acceptance: [
    { name: "buyer", type: "address" },
    { name: "seller", type: "address" },
    { name: "token", type: "address" },
    { name: "faceAmount", type: "uint256" },
    { name: "dueDate", type: "uint64" },
    { name: "invoiceHash", type: "bytes32" },
    { name: "invoiceNumberHash", type: "bytes32" },
    { name: "termsHash", type: "bytes32" },
    { name: "vault", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "expiry", type: "uint64" },
  ],
} as const;

export function acceptanceDigest(a: Acceptance, chainId: number, registry: Address): Hex {
  return hashTypedData({
    domain: acceptanceDomain(chainId, registry),
    types: ACCEPTANCE_TYPES,
    primaryType: "Acceptance",
    message: a,
  });
}

export function signAcceptance(account: LocalAccount, a: Acceptance, chainId: number, registry: Address): Promise<Hex> {
  return account.signTypedData({
    domain: acceptanceDomain(chainId, registry),
    types: ACCEPTANCE_TYPES,
    primaryType: "Acceptance",
    message: a,
  });
}

export function recoverAcceptanceSigner(a: Acceptance, sig: Hex, chainId: number, registry: Address): Promise<Address> {
  return recoverTypedDataAddress({
    domain: acceptanceDomain(chainId, registry),
    types: ACCEPTANCE_TYPES,
    primaryType: "Acceptance",
    message: a,
    signature: sig,
  });
}
