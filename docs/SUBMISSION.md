# DoraHacks BUIDL form: paste-ready text

**Name:** Hundi
**Tagline:** Instant cash against accepted invoices, repaid automatically through HSP.
**Track:** Agent Payments & A2A Settlement

**Problem.** Indian MSMEs wait around 73 days for money legally due in 45 (vendor-sourced), with about
₹8.1 lakh crore stuck in delayed payments (Economic Survey 2025-26 as reported; being verified). Regulated
invoice discounting (TReDS) does not reach the long tail or cross-border exporters. And as AI agents start
reading and paying invoices, every invoice becomes an attack surface: hidden prompts, swapped bank details,
double financing.

**Solution.** A seller's agent issues an invoice. The buyer's agent checks it with deterministic rules
(12 named refusal codes; an LLM can flag risk but never approve) and signs an EIP-712 acceptance. A lending
pool advances 90% to the seller in one transaction. The buyer's payment goes to a per-invoice vault whose
address is a CREATE2 function of every loan term, fixed before any money is lent, and the vault's code pays
the lender first, then the protocol fee, then the seller.

**How HSP is used.** HSP settles a signed payment to whatever `pay_to` the merchant's cart names, with no
escrow or splits. Hundi sets `pay_to` to the vault and makes the buyer agent refuse any cart that does not
pay the vault it accepted (8 named cart refusal codes, including payee swap and tampered cart). This maps
directly onto HSP Agentic Payment: the desk calls `create_order` with `pay_to` = vault, and the buyer agent
checks `prepare_payment`'s `pay_to`, token and `token_total_raw` before the wallet signs the EIP-3009
authorization. Honest status: HSP QA access needs IP allowlisting, which was not confirmed before the
deadline, so the demo runs in a labelled self-relay mode where the buyer wallet pays the vault directly,
only after the same checks pass.

**Architecture.** Solidity (Foundry, OpenZeppelin 5.7, immutable, no proxies): AcceptanceRegistry,
ReceivableFactory, ReceivableVault, ERC-4626 LiquidityPool. TypeScript SDK (viem, zod): canonical hashing,
EIP-712, verifyInvoice, verifyCart. Desk: seller, logistics, buyer, underwriter and keeper agents, live
dashboard, A2A agent card.

**Real vs simulated.** Real: contracts, acceptance, CREATE2 vault binding, advance, waterfall, on-chain
duplicate-invoice block, all live on HashKey Chain testnet (chain 133) with tx hashes in PROOF.md.
Testnet uses a labelled mock USDC.e; no mainnet deployment. Simulated: delivery attestation (signed by a simulated
logistics agent), HSP gateway (self-relay). Also built: an MCP server (6 tools) so any agent can use Hundi, a 36-case adversarial eval (36/36, zero false
accepts), and a triaged Slither run. Not done: independent audit, HSP gateway, mainnet. Full table in
CLAIMS.md.

**Roadmap.** HSP gateway adapter; MCP over HTTP; GST e-invoice
and e-way bill evidence; per-seller merchants; licensed lending partners.

**Links.** GitHub: https://github.com/HarshitAnand1/hundi · PROOF.md · JUDGES.md · testnet contracts: pool
0x469946b530392428e96A89C2a2988402b9C78a33, factory 0x2eAf2e93B8DA4a49A1359f81989D61F551564AD1, registry
0x41B734aC251e552FAc7F3a2828d26f63c320b6BC · demo video (add when recorded)

**Team.** Hundi: Harshit Anand, Dnyananda Thorat, Khushbu Sharma. HSP `merchant_name`: `Hundi`.
