# Hundi - project rules for Claude Code

## What this project is
Hundi finances buyer-accepted invoices on HashKey Chain. HSP pays into a per-invoice
vault that repays the lender first. Full brief: docs/HANDOFF.md. Read the relevant
section before touching code. Per-area specs: docs/spec/05-08.

## Layout
contracts/ (Foundry) | packages/sdk (HSP adapter, AP2 types, signers) |
apps/desk (API, agents, keeper) | apps/web (dashboard) | packages/mcp | docs/ | eval/

## Commands
- Contracts: cd contracts && forge build && forge test -vv
- SDK: pnpm --filter sdk test
- Desk: pnpm --filter desk test
- Everything: pnpm test:all (must pass before any commit)

## Non-negotiable rules
1. An LLM never approves a payment, acceptance or advance. Approval is deterministic code only.
2. Never invent addresses, token addresses, chain IDs, endpoints or signatures. Take them
   from config files or official docs and say where they came from. If unknown, stop and ask.
3. Never put secrets in code, tests, logs or commits. Use .env (gitignored). Never print private keys.
4. Money logic and signature code: write the test first, then the code. Use OpenZeppelin.
   Do not hand-roll crypto.
5. Settlement token is USDC.e only. Contracts are immutable (no proxies).
6. Do not edit files outside your assigned area without asking.
7. Mark anything unverified as [VERIFY] in comments and in CLAIMS.md.

## Workflow
- Non-trivial task: plan first, write the plan to tasks/todo.md, wait for approval.
- Failing test first, then implementation, then run all tests.
- Small commits, one concern each, clear messages.
- When finished, list what you did NOT verify.
- Record every choice that deviates from or resolves the handoff in docs/DECISIONS.md.

## Style
Solidity 0.8.x pinned, NatSpec on external functions, custom errors.
TypeScript strict, zod at every boundary, no any.
