# Proof

All transactions below are on **HashKey Chain testnet (chain id 133)**, confirmed by the RPC's
`eth_chainId`. Settlement uses a **labelled mock USDC.e** (`MockUSDCe`, 6 decimals), because the event's
official test USDC exists only on Ethereum Sepolia. No mainnet deployment (team decision, see
docs/DECISIONS.md). Explorer: look up any hash below on the HSK testnet explorer [VERIFY explorer URL].

## Deployment (chain 133, block 35219830)
Source: `contracts/deployments/133.json`, broadcast log `contracts/broadcast/Deploy.s.sol/133/run-latest.json`.

| Contract | Address | Deploy tx |
| --- | --- | --- |
| AcceptanceRegistry | `0x41B734aC251e552FAc7F3a2828d26f63c320b6BC` | `0x9db80e3defeb940f24cd53f29a07d57bd5e0b8e989a485ec7b91eb79863adb54` |
| ReceivableFactory | `0x2eAf2e93B8DA4a49A1359f81989D61F551564AD1` | `0xbe3d9462e4b07e47573e5550a45c5d17d551e5ad9f890628c66e19644c5790e0` |
| ReceivableVault (implementation) | `0x37Fd0e787fD7318bf50B22Cd2f3BE836a43C64c4` | created by the factory constructor |
| LiquidityPool (ERC-4626) | `0x469946b530392428e96A89C2a2988402b9C78a33` | `0xc38173cdd197e93a5b134a4f9ce51e91351ebc43531387d57132e55c7052e612` |
| MockUSDCe (testnet only) | `0x1B2957b8cc0635713bA8C566337609093877008D` | `0xa145297f662a2bd99ef4a6a364a889e7c7f83a1ca4de58f970c1323f8d02991e` |

Guardian and underwriter: burner operator `0x022A9421873509Bad1380D52587891D2658E236D`.
Deploy gas: 6,572,484 (0.0066 HSK).

## Lifecycle: one $10,000 invoice, 73 days, 90% advance (`pnpm e2e`)
| Role | Address |
| --- | --- |
| Buyer agent wallet | `0xdAA9f48bFBe293d4637C84864B92B29da765a2DE` |
| Seller agent wallet | `0x3f036C149fD05CDdF7f51aFf1583179c790FB17f` |
| Operator (LP, underwriter, keeper) | `0x022A9421873509Bad1380D52587891D2658E236D` |
| **Vault** (CREATE2, salt = termsHash) | `0xD7C2AB5c954ceb3e09f81eB596b0E73F02446B52` |
| termsHash | `0x9153a8843aae9d03a49731f1ce792522031149d856c95984bf1d4d299bb4a7ab` |

| Step | Tx |
| --- | --- |
| Mint mock USDC.e to operator | `0xa81f7264e14466b53489b068e24f13c1c933486e7a0396979597754bab33d298` |
| Approve pool | `0xcb71d2b7cc8bbcce79149f872600d1a0b7a3d1e8d34aeb75ab425d10324c494a` |
| Lender deposits 9,000 into pool | `0x6d77a88a5c97e2326407daa878e08490091623b5c5b817109e041f1439723a70` |
| Gas to buyer wallet | `0x5a51d57ff92c1bcb91297517fcb4323eac5279d855bdf6ca31234ce493b990f3` |
| Mock USDC.e to buyer wallet | `0x62d14711b89014b2e929daa8b1d8c3a966dc0a1193c941078c5d00b5f2970612` |
| **Advance**: record EIP-712 acceptance + create vault at predicted address + fund seller | `0x4b7b027bd10fb394092e86f863baa34a222e0c8a4209c99bfa18fef33d154080` |
| **Buyer pays 10,000 into vault** (self-relay, after verifyCart passed) | `0x4f56bd9ba72155d563a7a3701049e2c80697bf18077fb103be366205c5806706` |
| **Settle** (permissionless waterfall) | `0x36f5130e9ba0fccb026c9ac9618e9302a3e69e7b9b6420566a97755aab84af37` |

### Waterfall (from the `Settled` event)
| Recipient | Paid (USDC.e) | Expected (SDK maths) |
| --- | --- | --- |
| Lender (pool) | 9,143.999315 | 9,143.999315 ✓ |
| Protocol treasury | 10.000000 | 10.000000 ✓ |
| Seller at settlement (residual + 180 bond) | 1,026.000685 | — |

Seller received 8,820 at funding (advance 9,000 minus 180 bond). Total to seller ≈ 9,846; cost ≈ $154,
matching the HANDOFF 5.4 worked example (lender interest is per-second, hence the sub-cent difference).

## Attacks (same run)
| Attack | Result | Refusal |
| --- | --- | --- |
| Duplicate invoice, buyer agent | BLOCKED | `DUPLICATE_INVOICE` |
| Duplicate invoice, agent bypassed, straight to `AcceptanceRegistry.accept` (simulated call) | BLOCKED | revert `DuplicateInvoice` |
| Payee swap in invoice + prompt injection in notes | BLOCKED | `PAYEE_CHANGED` |
| Merchant-signed cart paying an attacker | BLOCKED | `PAYTO_NOT_VAULT` |
| Cart amount edited after signing | BLOCKED | `CART_HASH_MISMATCH`, `AMOUNT_MISMATCH` |

Result line: `E2E PASS`. Desk journal of this run: `apps/desk/data/133.json` (view with
`HSK_CHAIN_ID=133 pnpm -C apps/desk start`, http://localhost:8787).

## HSP relayer check
Not applicable: no HSP gateway payment was made (self-relay mode, labelled).

## Tests
`pnpm test:all`: 75 Foundry tests (incl. 2 fuzz, 6 invariants), 51 SDK tests, 4 desk tests, all passing.
A fresh clone passes the README quick start.
