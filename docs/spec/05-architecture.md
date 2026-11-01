> Extracted from docs/HANDOFF.md Section 5. Edit the handoff, not this file, or record changes in docs/DECISIONS.md.

## 5. System architecture

### 5.1 Components

   Component                                Technology                  Job

    ReceivableFactory                       Solidity, Foundry           Deploys per-invoice vaults at addresses
                                                                        computed from the terms (CREATE2
                                                                        clones)

    ReceivableVault                         Solidity                    Holds the waterfall: Open → Funded →
                                                                        Settled or Defaulted

    AcceptanceRegistry                      Solidity, EIP-712, ERC-     Records buyer-signed acceptances;
                                            1271                        blocks duplicate invoices

    LiquidityPool                           Solidity, ERC-4626          Lenders deposit USDC.e; funds
                                                                        advances within on-chain limits

    ReceivableNote                          ERC-721                     Transferable lender claim; vault pays the
   (L2)                                                                 current owner

   Desk                                     TypeScript, Fastify,        HSP merchant of record, webhook
                                            SQLite                      handler, keeper, REST API, live event
                                                                        stream

   Agents                                   TypeScript, A2A, AP2        Seller, buyer, underwriter; deterministic
                                            types                       policy code with an LLM for extraction
                                                                        and memos only

   MCP server                               TypeScript                  Lets any agent issue, accept, finance and
                                                                        pay invoices

   Web                                      Next.js                     Live dashboard: timeline, waterfall,
                                                                        attack panel, evidence pack

### 5.2 Lifecycle, step by step
 1. Issue. The seller agent creates a canonical invoice JSON (seller, buyer, token, amount,
    due date, goods/service hash, PO reference, invoice number) and its invoiceHash .
 2. Terms. The desk builds Terms (Section 6.1), computes termsHash , and computes
     vault = factory.predictVault(terms) .
 3. Accept. The buyer agent runs verifyInvoice (Section 8). On pass, it signs an EIP-712
    Acceptance that includes vault , termsHash , amount and due date. Anyone can
     submit it to AcceptanceRegistry.accept .
 4. Create vault. factory.createVault(terms) deploys the vault at the predicted
    address (requires a recorded acceptance).
 5. Underwrite. The underwriter agent proposes advance rate and fee within the pool’s
    on-chain bounds and writes a risk memo. Deterministic numbers; LLM text only
    explains them.
 6. Advance. pool.advance(...) checks the registry, bounds and exposure caps, then
     calls vault.fund . The seller receives advance minus bond.
 7. Mature. At or near the due date, the desk creates the HSP order just-in-time (HSP cart
    expiry is unknown, [VERIFY]) with pay_to = vault and amount = face value.
 8. Pay. The buyer agent runs verifyCart (code, not a prompt): merchant signature, cart
     hash, pay_to == predictVault(terms from the stored acceptance) , amount,
     token, due date. If it passes, it signs the payment authorization and submits the AP2
     Payment Mandate to HSP.
 9. Settle. HSP’s relayer moves USDC.e to the vault. The desk’s webhook handler confirms
    it on-chain; anyone calls vault.settle() . The waterfall pays out.
 10. Record. Events update the dashboard and the buyer’s on-chain payment record. If
   unpaid past the default window, declareDefault() runs.

### 5.3 Vault state machine
 Open (deployed, unfunded) → Funded → Settled (on time or late) or Defaulted . Open
→ Cancelled if the acceptance expires unfunded. If the buyer pays while still Open
(prepaid), settle() pays the seller in full and the vault can never be funded afterwards.

### 5.4 Money math (worked example, USD)
Face value $10,000; advance 90%; fee 8% a year; tenor 73 days (exactly 0.2 of a year);
bond 2% of advance; protocol fee 0.1% of face.

   Line                                           Calculation           Amount

   Advance                                        90% × 10,000          $9,000

   Bond held                                      2% × 9,000            $180

   Seller receives at funding                     9,000 − 180           $8,820

   Discount fee                                   9,000 × 8% × 73/365   $144

   Protocol fee                                   0.1% × 10,000         $10

   Lender due at maturity                         9,000 + 144           $9,144

   Seller residual at maturity                    10,000 − 9,144 − 10   $846

   Bond returned                                                        $180

   Seller total                                   8,820 + 846 + 180     $9,846

   Total cost to seller                                                 $154 (1.54%)

Check: 9,846 + 144 + 10 = 10,000. Make the dashboard show this table live, with days-to-
cash falling from 73 to minutes.

### 5.5 Late, partial and default rules
     Late: after the due date, late interest accrues to the lender on the advance at
     lateAnnualBps , paid ahead of the protocol fee.
     Partial payment: all funds go to the lender until lender due is covered; the vault stays
     Funded until fully paid or defaulted.
     Overpayment: any amount above face value goes to the seller.
     Default: after dueDate + defaultSeconds , anyone may call declareDefault() . The
     bond is forfeited to the lender up to the shortfall. The buyer’s negative record is
     written. The evidence pack is generated.
     Pull fallback: payments are pushed to recipients, but if a transfer fails (for example a
     blocklisted address), the amount waits in the vault for claim() . One bad recipient
     must never freeze the others.

### 5.6 Design rules
     Settle in USDC.e only. With the EIP-3009 authorization the recipient is inside the
     payer’s signature. For USDT’s Permit2 path the recipient is not, which weakens the
     guarantee [VERIFY].
     Label every settlement’s rail honestly: HSP gateway only when the funding transfer
     was sent by HSP’s relayer (a competitor lists
      0x1aaA5E4371aAdf96bEfb5bd2Af4d896FD16915Ea , [VERIFY]), otherwise self-relayed.

     Reputation only from funded receivables. A competitor’s audit found zero-capital
     vaults could poison reputation. We write records only after real funding and
     settlement, bound to the actual parties.
     No upgradeable contracts for the vault. Immutable is easier to audit and to claim.

