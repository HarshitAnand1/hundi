# Plan: Layer L0 (submittable core)

Written 2026-11-01 14:30 IST. Deadline 21:30 IST on 2026-11-02 (corrected; submit target 20:45 on 2 Nov). ~7 h left, so the
handoff's schedule is compressed: phases A–F run today and L1 is cut down to what fits.
Status: AWAITING APPROVAL. No code yet.

## Phase A: access and decisions (now → 15:30)
- [x] Install toolchain: Foundry 1.8.7, pnpm 10.34.9 (slither deferred to L1)
- [x] Mainnet rule resolved: mainnet REQUIRED for demo selection (see DECISIONS.md). Build on testnet first, deploy mainnet before 21:30
- [ ] Ask organisers for HSP merchant credentials (support group https://t.me/+M5yaRB-u4PRiNWM1)
- [ ] Read the official HSP Agentic Payment guide: https://dorahacks.io/hackathon/hskchainindia/agentic-payment-guide
- [ ] Confirm from official docs and write to config with source noted in DECISIONS.md:
      chain IDs (133 / 177), mainnet RPC, USDC.e address, HSP base URL, HSP relayer address
- [ ] Fund a fresh burner deployer: testnet HSK from faucet now; mainnet HSK + small USDC.e later
- [x] Freeze `Terms` and `Acceptance` structs → `contracts/src/Types.sol`; ABIs in `packages/sdk/src/abi/`
- [ ] `git init`, first commit (with .gitignore already in place)

## Phase B: contracts + tests — DONE 15:05: 74 tests (unit, 2 fuzz, 6 invariants) passing; deploy script dry-run OK on local anvil
Files:
- `contracts/foundry.toml`, `contracts/remappings.txt`, lockfile/submodule pin for OZ
- `contracts/src/Types.sol` — Terms, Acceptance, hashing helpers
- `contracts/src/AcceptanceRegistry.sol` — EIP-712 + SignatureChecker (ERC-1271), nonce, expiry, invoiceKey single-use
- `contracts/src/ReceivableFactory.sol` — `predictVault`, `createVault` (Clones.cloneDeterministic, salt = termsHash, requires acceptance)
- `contracts/src/ReceivableVault.sol` — Open→Funded→Settled/Defaulted/Cancelled; `fund`, `settle`, `declareDefault`, `claim`, `cancel`, `amountDue`; push with pull fallback
- `contracts/src/LiquidityPool.sol` — ERC-4626; `advance` with bounds + per-buyer/seller caps; guardian pause of new advances only
- `contracts/test/mocks/MockUSDCe.sol` (+ blocklist + malicious token mocks)
- `contracts/test/Invariants.t.sol` — invariants 1–8 (9 deferred: no reputation in L0) — WRITTEN FIRST
- `contracts/test/{Registry,Factory,Vault,Pool}.t.sol` — unit tests for every revert; waterfall fuzz (sum of payouts == funds in); worked example 10,000 → 8,820 / 9,144 / 10 / 846 / 180
- `contracts/script/Deploy.s.sol` → writes `contracts/deployments/<chainId>.json`

## Phase C: first real payment (parallel with B, as soon as a vault address exists)
- [ ] Small real USDC.e payment into a predicted/created vault address (via HSP if credentials, else self-relay EIP-3009) — answers "can pay_to be a contract?"
- [ ] If rejected: receiver-wallet forwarder fallback, recorded in DECISIONS.md

## Phase D: sdk + desk + e2e — DONE 18:10: SDK 51 tests, desk 4 tests, e2e (5 attacks blocked, waterfall exact) passes on anvil
- `pnpm-workspace.yaml`, root `package.json` (`test:all`), `tsconfig.base.json`
- `packages/sdk/src/types.ts` — zod schemas: Invoice, Terms, Acceptance, Cart, PaymentMandate
- `packages/sdk/src/verifyInvoice.ts` + test — all 12 refusal codes, table-driven
- `packages/sdk/src/verifyCart.ts` + test — all 8 refusal codes, table-driven
- `packages/sdk/src/hsp/{merchantClient,payerClient,webhook,reconcile,rails}.ts` behind one interface; `HSP_MODE=gateway|self-relay`
- `apps/desk/` — Fastify + SQLite: issue/accept/advance/pay endpoints, webhook, keeper, SSE event stream
- `scripts/e2e.ts` — L0 scenarios: happy path, duplicate invoice, payee swap, tampered cart (others later); prints tx hashes

## Phase E: deploy + minimal dashboard — DONE 2 Nov: testnet 133 deploy + e2e PASS (PROOF.md); mainnet skipped (team decision)
- [ ] Deploy + verify on Blockscout (mainnet if confirmed, otherwise testnet; label honestly)
- [ ] Run one real lifecycle; hashes into PROOF.md
- `apps/web/` — Next.js: timeline + live waterfall table from events (fallback: single static page reading the desk SSE stream if time is short)

## Phase F: submit (20:30 → 21:15 hard stop)
- [ ] README (3-command fork demo), JUDGES.md, CLAIMS.md (real / fork / simulated / roadmap), PROOF.md
- [ ] DoraHacks BUIDL form (HANDOFF 15.1) — submit with ≥15 min buffer
- [ ] Short demo video if time permits; otherwise record for Demo Day (4 Nov)

## Explicitly cut from today (L1/L2 → 2–4 Nov, if submissions can be updated — check, don't assume)
Full 70-test bar, Slither/AUDIT.md, eval set run twice, CI, MCP server, ERC-721 note,
attack panel, evidence pack, late/default on mainnet.
Done 2 Nov 19:40: eval set (36/36), MCP server (6 tools, stdio), Slither triage (AUDIT.md).
