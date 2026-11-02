# Proof

## Deployments
| Network | Chain id | Status | Addresses |
| --- | --- | --- | --- |
| HashKey Chain mainnet | 177 [VERIFY] | _pending: deploy in progress_ | `contracts/deployments/177.json` |
| HashKey Chain testnet | 133 [VERIFY] | _pending: deploy in progress_ | `contracts/deployments/133.json` |

## Scenario transactions
_Filled from `pnpm e2e` output once deployed._

| Scenario | Network | Tx |
| --- | --- | --- |
| Pool deposit | | |
| Advance (accept + create vault + fund) | | |
| Buyer payment into vault (self-relay) | | |
| Settle (waterfall) | | |

## Attacks (from e2e)
| Attack | Result | Refusal codes |
| --- | --- | --- |
| Duplicate invoice (agent) | BLOCKED | DUPLICATE_INVOICE |
| Duplicate invoice (on-chain, agent bypassed) | BLOCKED | DuplicateInvoice (revert) |
| Payee swap in invoice with prompt injection | BLOCKED | PAYEE_CHANGED |
| Payee swap in merchant-signed cart | BLOCKED | PAYTO_NOT_VAULT |
| Cart tampered after signing | BLOCKED | CART_HASH_MISMATCH, AMOUNT_MISMATCH |

Local anvil run (chain 31337, mock token): waterfall lender 9,143.999589 = expected, protocol 10.000000 =
expected, seller 1,026.000411 (residual + bond). `E2E PASS`.

## HSP relayer check
Not applicable yet: no HSP gateway payment has been made (self-relay mode).

## Tests
`pnpm test:all`: 75 Foundry tests (incl. 2 fuzz, 6 invariants), 51 SDK tests, 4 desk tests, all passing.
