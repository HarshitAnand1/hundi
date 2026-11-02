# Claims and evidence

Status values: **Real on mainnet** · **Real on testnet** · **Local chain only** · **Simulated** · **Roadmap**.
Statuses marked _pending_ change once the deployment in PROOF.md exists.

## Product claims
| Claim | Evidence | Status |
| --- | --- | --- |
| Vault address is fixed by the terms before funding (CREATE2, salt = termsHash) | `ReceivableFactory.predictVault`; factory tests; e2e checks the vault exists at the predicted address | Local chain only (_pending_ testnet / mainnet) |
| Buyer acceptance is an EIP-712 signature recorded on-chain; ERC-1271 wallets supported | `AcceptanceRegistry`; registry tests incl. MockERC1271Wallet | Local chain only (_pending_) |
| Lender is repaid before protocol and seller | `ReceivableVault._settle`; `invariant_lender_first`; waterfall fuzz; e2e asserts lender paid = SDK expectation | Local chain only (_pending_) |
| Worked example: $8,820 at funding; $9,144 lender / $10 protocol / $846 + $180 bond to seller | `test/ReceivableVault.t.sol`, `packages/sdk/test/money.test.ts`, e2e output | Local chain only (_pending_) |
| An invoice can be financed only once | `invoiceKeyUsed` in registry; `invariant_single_financing`; e2e duplicate attack (agent + on-chain) | Local chain only (_pending_) |
| LLM never approves; prompt injection in invoice text cannot change a decision | `verifyInvoice` (LLM signal can only add `LLM_RISK_FLAG`); SDK injection tests; e2e attack | Real (code + tests); no LLM is called in L0 |
| Buyer agent refuses carts not paying the accepted vault | `verifyCart` `PAYTO_NOT_VAULT`; SDK tests; e2e attack | Local chain only (_pending_) |
| Payment through HSP | Self-relay transfer only; gateway adapter not built | **Simulated** (self-relay, labelled) |
| HSP accepts a contract address as `pay_to` | Not tested against HSP | Roadmap / [VERIFY] |
| Delivery attestation | EIP-191 signature from a simulated logistics agent | **Simulated** |
| Underwriter memo | Deterministic template from the numbers; no model call | Real (template) |
| Late interest and default with bond forfeiture | Vault unit tests | Tested in Foundry only |
| MCP server for other agents | — | Roadmap |
| Agent card at `/.well-known/agent-card.json` | `apps/desk/src/server.ts` | Real (local server) |

## Market statistics (source quality)
| Claim | Source | Status |
| --- | --- | --- |
| ~₹8.1 lakh crore stuck in delayed MSME payments | Economic Survey 2025-26 as reported by outlets | [VERIFY] against the Survey itself |
| 73 days average vs 45-day legal limit | Recordent (vendor) via a fintech news site | Vendor-sourced |
| Section 43B(h) tax deduction rule since April 2024 | Secondary articles | [VERIFY] |
| TReDS ~₹40,000 cr (FY22) → ₹3.47 lakh cr (FY26) | Secondary article | [VERIFY] |
| Typical invoice discounting 5–8% p.a. | One secondary article | [VERIFY], not a guarantee |

## Unverified technical assumptions
- HashKey Chain IDs 133 (testnet) / 177 (mainnet) and Cancun EVM support: [VERIFY] at deploy (`cast chain-id`).
- USDC.e address: taken from official token docs at deploy time; recorded in `contracts/deployments/<id>.json`.
- HSP cart format, ES256K merchant signature, relayer address, webhook scheme: not confirmed; not used.
- Blockscout verifier URL for `forge --verify`: unconfirmed.

## What we did not do
No Slither, no independent audit, no eval set, no HSP gateway payment, no legal or regulatory claims.
