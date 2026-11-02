# Decisions log

Running log of choices and why. When the handoff conflicts with an official document,
the official document wins; record the correction here.

| Date (IST) | Decision | Why | Source |
|---|---|---|---|
| 2026-11-01 14:30 | Repo scaffolded per HANDOFF Section 11 and 12.2 | Start of build | docs/HANDOFF.md |
| 2026-11-01 14:45 | Start on HSK testnet (chain ID 133 [VERIFY]); move to mainnet before submission | Team decision; get the lifecycle working cheaply first | User |
| 2026-11-01 14:45 | Mainnet IS required: event page says projects without HSK mainnet deployment forfeit demo selection, and winners must be on mainnet. Resolves the HANDOFF Section 1 conflict | Official event page text, pasted by user | dorahacks.io/hackathon/hskchainindia/detail |
| 2026-11-01 14:45 | Deadline confirmed: 1 Nov 2026 21:30 IST; system closes automatically, no late submissions | Event page body text (the sidebar widget shows 2026/11/02 09:30 — ignore it, body text is explicit) | Event page |
| 2026-11-01 14:45 | HSP API docs URL is https://hashkey-merchant.github.io/#/ (HANDOFF had /en/index.html) | Event page | Event page |
| 2026-11-01 14:45 | New official resources: HSP Agentic Payment guide https://dorahacks.io/hackathon/hskchainindia/agentic-payment-guide ; dev one-pager https://hashfans.io/dev-onepager ; support group https://t.me/+M5yaRB-u4PRiNWM1 | Event page | Event page |
| 2026-11-01 14:45 | In-person demo in Mumbai gets priority for demo selection; pitch list announced 3 Nov | Event page | Event page |
| 2026-11-01 14:45 | Toolchain: Foundry 1.8.7, pnpm 10.34.9, Node 22.22.1 | Installed this session | Local |
| 2026-11-01 15:05 | Terms and Acceptance structs FROZEN in contracts/src/Types.sol; ABIs exported to packages/sdk/src/abi | Every other component codes against them (HANDOFF 12.5) | — |
| 2026-11-01 15:05 | Added `invoiceNumberHash` to Acceptance | HANDOFF 6.2 defines invoiceKey = keccak256(seller, buyer, invoiceNumberHash) but Acceptance had no such field. The buyer signs it, so duplicate detection is buyer-attested | HANDOFF 6.2 |
| 2026-11-01 15:05 | Acceptance `expiry` = submission deadline AND funding deadline; vault is cancellable after it if unfunded | HANDOFF 5.3 "Open → Cancelled if the acceptance expires unfunded" | HANDOFF 5.3 |
| 2026-11-01 15:05 | Underwriting (advanceBps, fee) happens BEFORE acceptance, not after | Those numbers are inside Terms, which are hashed into the vault address the buyer signs. HANDOFF 5.2 lists underwrite as step 5, after accept; that order is impossible | HANDOFF 5.2, 6.1 |
| 2026-11-01 15:05 | Discount fee = advance × feeAnnualBps × (dueDate − fundedAt) / 365d, fixed at funding | Worked example (73 days → $144) matches when funded at issue | HANDOFF 5.4 |
| 2026-11-01 15:05 | Late interest accrues on the advance from dueDate + graceSeconds (grace waives it entirely); frozen at default | HANDOFF 5.5 does not say whether grace is waived or deferred; waived is simpler and kinder to the seller | HANDOFF 5.5 |
| 2026-11-01 15:05 | Unsolicited dust while Open is ignored at funding and later flows through the waterfall; fund() reverts only if pending ≥ face (prepaid) | Otherwise 1 wei sent to a predicted vault would permanently block its financing (griefing) | HANDOFF 6.5 |
| 2026-11-01 15:05 | After default, later recoveries still go lender (frozen due) → protocol → seller; state stays Defaulted | Monotonic state + lender first | HANDOFF 6.4 #3, #7 |
| 2026-11-01 15:05 | Pool.advance restricted to an immutable `underwriter` address; pool bounds/caps are immutable constructor params | Pool money should not be advanced by arbitrary callers; immutable bounds keep "guardian can only pause" true | HANDOFF 6.2, 15.8 |
| 2026-11-01 15:05 | Pool fee income recognised on receipt; principal carried at par, reduced principal-first on repayment, written off on default; vault notifies pool via try/catch onVaultUpdate(), sync() also permissionless | Conservative NAV, no iteration over positions | — |
| 2026-11-01 15:05 | Invariant 9 (reputation integrity) deferred: no reputation records in L0 | Scope; buyer payment record is L2 | HANDOFF 13 |
| 2026-11-01 15:05 | Solidity 0.8.28, OpenZeppelin v5.7.0, forge-std v1.17.0 (git submodules), evm_version = cancun | OZ 5.7 uses mcopy. [VERIFY] HSK Chain supports Cancun | — |
| 2026-11-01 15:05 | Deploy script may deploy MockUSDCe (DEPLOY_MOCK_TOKEN=true) only on chain 133 / local; recorded as tokenIsMock in deployments json | Testnet USDC.e availability unknown [VERIFY]; must be labelled simulated in CLAIMS.md | — |
| 2026-11-01 16:25 | SDK pinned: viem 2.57.14, zod 4.6.7, vitest 5.0.5, typescript 5.9.3 (not 7.x: newest major, less proven), Node 22 | Pin everything (HANDOFF 12.9) | — |
| 2026-11-01 16:25 | verifyCart takes HSP cart hashing and merchant-signature checks as injected functions; self-relay mode uses Hundi's own canonical-JSON + EIP-191 scheme, clearly labelled | HSP wire format / ES256K details not yet confirmed from official docs; must not be guessed | HANDOFF 7 |
| 2026-11-01 16:25 | Delivery attestation = EIP-191 signature by a trusted attester over keccak256("hundi.delivery.v1", invoiceHash, keccak(poRef), goodsHash) | Simulated logistics agent (honest limit, HANDOFF 8) | — |
| 2026-11-01 16:25 | verifyInvoice/verifyCart return ALL applicable refusals in spec order, not just the first; dependency errors fail closed | Better evidence for judges and eval; HANDOFF 8 fail-closed rule | HANDOFF 8 |
| 2026-11-01 16:25 | Cross-language vectors: contracts/test/Vectors.t.sol and packages/sdk/test/vectors.test.ts assert identical termsHash, invoiceKey and EIP-712 digest | Silent EIP-712 bugs (HANDOFF 12.9) | — |
| 2026-11-01 18:10 | Desk L0 = plain node:http server + JSON-file journal (apps/desk/data/<chainId>.json), not Fastify + SQLite | 3.5 h to hard close; read-only API + SSE is all the demo needs; single writer per chain | HANDOFF 8 / todo Phase D |
| 2026-11-01 18:10 | Dashboard = one static page (apps/web/index.html) served by the desk, not Next.js | Plan's stated fallback when time is short | todo Phase E |
| 2026-11-01 18:10 | Demo role wallets (buyer, seller, logistics, merchant, attacker, treasury) derived as keccak256(operatorKey ‖ "hundi.role:<label>"); operator = LP + underwriter + keeper | One burner key to fund; every role wallet and any funds sent to it are recoverable from that burner | — |
| 2026-11-01 18:10 | Self-relay payment = buyer wallet ERC-20 transfer of USDC.e to the vault, only after verifyCart passes; HSP gateway rail not wired in L0, webhook returns 501 | No HSP credentials or confirmed wire format yet; refuse unauthenticated webhooks rather than trust them | HANDOFF 7 |
| 2026-11-01 18:10 | Underwriter memo is a deterministic template, no LLM call in L0 | LLM may only explain; nothing to gain from a model call under time pressure | HANDOFF 8 |
| 2026-11-01 18:10 | scripts/e2e.ts runs happy path + duplicate invoice (agent and on-chain bypass) + payee swap (invoice with prompt injection, and merchant-signed cart) + tampered cart; local run on anvil passes | L0 scenario list | todo Phase D |
| 2026-11-02 18:15 | Deadline is 2026-11-02 21:30 IST (user confirmed), not 1 Nov; earlier entry superseded | User statement; matches the event page's sidebar widget | event page |
| 2026-11-02 18:15 | Deployer = fresh burner from `cast wallet new`, never a wallet holding other assets | Key sits in plaintext .env; isolates risk and keeps on-chain history clean | HANDOFF 12.9 |
| 2026-11-02 18:30 | HSK testnet runs use the labelled MockUSDCe (DEPLOY_MOCK_TOKEN=true). Circle test USDC is on Ethereum Sepolia (0x1c7D…7238), a different chain, so it cannot pay an HSK vault | Event page "Claim USDC" section lists test USDC only on Sepolia; no HSK testnet USDC.e is given. Mainnet still uses real USDC.e | event page (pasted by user) |
