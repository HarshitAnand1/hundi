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
pay the vault it accepted (8 named cart refusal codes, including payee swap and tampered cart). Honest
status: the HSP gateway adapter is not wired yet; the demo runs in a labelled self-relay mode where the
buyer wallet pays the vault directly, only after the same cart checks pass.

**Architecture.** Solidity (Foundry, OpenZeppelin 5.7, immutable, no proxies): AcceptanceRegistry,
ReceivableFactory, ReceivableVault, ERC-4626 LiquidityPool. TypeScript SDK (viem, zod): canonical hashing,
EIP-712, verifyInvoice, verifyCart. Desk: seller, logistics, buyer, underwriter and keeper agents, live
dashboard, A2A agent card.

**Real vs simulated.** Real: contracts, acceptance, CREATE2 vault binding, advance, waterfall, on-chain
duplicate-invoice block (see PROOF.md for network). Simulated: delivery attestation (signed by a simulated
logistics agent), HSP gateway (self-relay). Not done: Slither / audit, eval set, MCP server. Full table in
CLAIMS.md.

**Roadmap.** HSP gateway adapter; MCP server so any agent can issue, accept and pay invoices; GST e-invoice
and e-way bill evidence; per-seller merchants; licensed lending partners.

**Links.** GitHub: https://github.com/HarshitAnand1/hundi · PROOF.md · JUDGES.md · verified contracts
(add Blockscout links after mainnet deploy) · demo video (add when recorded)

**Team.** _names and roles: to fill_
