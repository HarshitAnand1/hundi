# Claims and evidence

Status values: **Real on testnet** (HashKey Chain testnet, chain 133, tx hashes in PROOF.md) · **Simulated** · **Roadmap**.
No mainnet deployment (team decision). Testnet settlement token is a labelled mock USDC.e.

## Product claims
| Claim | Evidence | Status |
| --- | --- | --- |
| Vault address is fixed by the terms before funding (CREATE2, salt = termsHash) | `ReceivableFactory.predictVault`; factory tests; e2e checks the vault exists at the predicted address | Real on testnet |
| Buyer acceptance is an EIP-712 signature recorded on-chain; ERC-1271 wallets supported | `AcceptanceRegistry`; registry tests incl. MockERC1271Wallet | Real on testnet |
| Lender is repaid before protocol and seller | `ReceivableVault._settle`; `invariant_lender_first`; waterfall fuzz; e2e asserts lender paid = SDK expectation | Real on testnet |
| Worked example: $8,820 at funding; $9,144 lender / $10 protocol / $846 + $180 bond to seller | `test/ReceivableVault.t.sol`, `packages/sdk/test/money.test.ts`, e2e output | Real on testnet |
| An invoice can be financed only once | `invoiceKeyUsed` in registry; `invariant_single_financing`; e2e duplicate attack (agent + on-chain) | Real on testnet |
| LLM never approves; prompt injection in invoice text cannot change a decision | `verifyInvoice` (LLM signal can only add `LLM_RISK_FLAG`); SDK injection tests; e2e attack | Real (code + tests); no LLM is called in L0 |
| Buyer agent refuses carts not paying the accepted vault | `verifyCart` `PAYTO_NOT_VAULT`; SDK tests; e2e attack | Real on testnet |
| Payment through HSP | Self-relay transfer only; gateway adapter not built | **Simulated** (self-relay, labelled) |
| HSP accepts a contract address as `pay_to` | HSP guide: `create_order` takes a caller-supplied `pay_to` (any 42-char EVM address) and EIP-3009 transfers can credit a contract. Not executed against HSP | Designed; not run (QA allowlisting not confirmed in time) |
| Delivery attestation | EIP-191 signature from a simulated logistics agent | **Simulated** |
| Underwriter memo | Deterministic template from the numbers; no model call | Real (template) |
| Late interest and default with bond forfeiture | Vault unit tests | Tested in Foundry only (not run on testnet) |
| MCP server for other agents (6 tools, stdio) | `packages/mcp`; `scripts/mcp-smoke.ts` drives it with a real MCP client: lifecycle settles, payee swap refused | Real (local chain); HTTP transport is roadmap |
| Acceptance gate holds on 36 adversarial / benign cases | `eval/cases.json` (answer key), `eval/RESULTS.md`: 36/36, 0 false accepts, 0 false refusals | Real (deterministic, no model) |
| Static analysis | Slither 0.11.3, 22 results triaged in AUDIT.md, no code change needed | Real |
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
- Testnet chain id 133 confirmed by RPC; contracts compiled for Cancun deployed and ran the full lifecycle there. Mainnet id 177: [VERIFY], unused.
- Real USDC.e not used: testnet runs on MockUSDCe (the event's official test USDC is Sepolia-only).
- HSP flow now confirmed from the official guide (MCP tools, x402 v2, EIP-3009 / Permit2, gateway broadcasts).
  Not executed: QA access needs IP allowlisting, which was not confirmed before the deadline.
- Contracts not source-verified on an explorer yet.

## What we did not do
No mainnet deployment, no real USDC.e, no independent human audit, no HSP gateway payment, no LLM call in
the demo (the gate accepts an LLM risk signal as data), no legal or regulatory claims.
