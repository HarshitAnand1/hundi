# Audit

**Scope:** `contracts/src` (AcceptanceRegistry, ReceivableFactory, ReceivableVault, LiquidityPool, Types).
**Tool:** Slither 0.11.3, 80 detectors, informational excluded, `lib/`, `test/`, `script/` filtered.
Run on 2026-11-02. Reproduce with `cd contracts && slither . --filter-paths "lib/|test/|script/" --exclude-informational`.

**Result:** 22 results (0 high, 6 medium, 16 low). After triage: **no exploitable issue, no code change
needed**. The testnet deployment in PROOF.md is the same code that was analysed.

No independent human audit has been done. This is a hackathon prototype; do not hold real funds in it.

## Medium
| # | Detector | Location | Triage | Status |
| --- | --- | --- | --- | --- |
| M1 | incorrect-equality | `ReceivableVault._settle`: `pending == 0` | Early return on an empty balance. Nobody gains by making the balance exactly zero; an attacker who donates dust just pays the seller | False positive |
| M2 | incorrect-equality | `ReceivableVault._push`: `amount == 0` | Skips a zero transfer; no balance dependency | False positive |
| M3 | incorrect-equality | `_settle`: `lenderPaid == lenderDue && protocolPaid == protocolFee` | Both sides are built with `Math.min(pending, due - paid)`, so they reach equality exactly and can never exceed it. Covered by `invariant_lender_first`, `invariant_conservation` and the waterfall fuzz | False positive |
| M4 | uninitialized-local | `LiquidityPool.sync`: `next`, `writtenOff` | Zero is the intended default (Settled/Cancelled ⇒ no principal outstanding; only Defaulted sets `writtenOff`). Covered by `invariant_pool_outstanding_matches_positions` | By design |
| M5 | (same as M4) | | | By design |
| M6 | unused-return | `LiquidityPool.advance` ignores `factory.createVault(t)` | The vault address is computed first with `predictVault` (same CREATE2 salt and implementation), and `fund` is called on that address; a mismatch is impossible and would revert on `fund`. Hardening for a v2: assert the returned address equals the prediction | Accepted, noted for v2 |

## Low
| # | Detector | Location | Triage | Status |
| --- | --- | --- | --- | --- |
| L1–L2 | shadowing-local | `_settle` locals `lenderDue`, `pending` shadow view functions | Readability only | Accepted |
| L3–L5 | missing-zero-check | Pool constructor `guardian_`, `underwriter_`; `ReceivableVault.fund` `lender_` | `fund` is callable only by the pool, which passes `address(this)`. A zero guardian/underwriter is a deploy misconfiguration that disables advances or pausing; it cannot move funds. The deploy script defaults both to the broadcaster | Accepted |
| L6–L7 | reentrancy-benign / reentrancy-events | `ReceivableFactory.createVault` | The only external call is to our own freshly cloned vault's `initialize`; state written after it is the `isVault` flag. No untrusted callee | False positive |
| L8–L16 | timestamp | expiry, funding deadline, due date, grace and default windows | Business rules are on day scales; a few seconds of validator drift does not matter | By design |

## Other review done
- Reentrancy: `nonReentrant` on vault entry points; malicious-token tests (`ReentrantToken`) in `test/ReceivableVault.t.sol`.
- Blocklisted payee (USDC-style blocklist): push fails over to `owed` / `claim()`; tested with `MockUSDCe.setBlocked`.
- Signature malleability and smart-wallet buyers: OpenZeppelin `SignatureChecker` (ECDSA + ERC-1271), tested.
- Cross-language EIP-712 agreement: `contracts/test/Vectors.t.sol` ⇔ `packages/sdk/test/vectors.test.ts`.
