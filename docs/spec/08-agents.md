> Extracted from docs/HANDOFF.md Section 8. Edit the handoff, not this file, or record changes in docs/DECISIONS.md.

## 8. Agents, AP2/A2A and MCP

   Agent                         Role                                   Notes

   Seller agent                  A2A merchant role. Issues invoices,    Publishes an Agent Card at
                                 requests advances                      /.well-known/agent-card.json

   Buyer agent                   A2A payment role. Verifies             All decisions in code
                                 invoices, signs acceptance, pays at
                                 maturity

   Underwriter                   Proposes advance and fee within        Numbers are deterministic; LLM
   agent                         pool bounds; writes a risk memo        only explains

   Keeper                        Triggers createVault , advance ,       All functions are permissionless;
                                  settle , declareDefault               anyone could run it

   Desk                          HSP merchant of record, API, event     Honest limit: one merchant of
                                 stream                                 record for all sellers

The LLM boundary (the most important rule). The LLM may (a) extract fields from
invoice text into a strict JSON schema, (b) write risk memos, and (c) raise a risk flag. It
may never approve anything. Approval means every deterministic check passes, plus a
human approval above a configured threshold. All counterparty text is untrusted data:
never place it in an instruction position, always validate LLM output against a zod schema,
and fail closed.

 verifyInvoice refusal codes (named, returned to the caller, tested). SCHEMA_INVALID ,
 SIGNATURE_INVALID , VENDOR_NOT_ALLOWED , OVER_CAP , DUPLICATE_INVOICE ,
 PO_MISMATCH , DELIVERY_NOT_ATTESTED , DUE_DATE_OUT_OF_POLICY , TOKEN_MISMATCH ,
 PAYEE_CHANGED , HUMAN_APPROVAL_REQUIRED , LLM_RISK_FLAG .

 verifyCart refusal codes. CART_SIGNATURE_INVALID , CART_HASH_MISMATCH ,
 PAYTO_NOT_VAULT , AMOUNT_MISMATCH , TOKEN_MISMATCH , DUE_DATE_MISMATCH ,
 ACCEPTANCE_NOT_FOUND , ALREADY_SETTLED .

Delivery attestation (honest limit). In the prototype, proof of delivery is a signed
attestation from a trusted party (simulated logistics agent). State this plainly. Roadmap:
GST e-invoice and e-way bill data.

MCP server tools. issue_invoice , accept_invoice , request_advance , pay_invoice ,
 get_receivable , list_receivables . Offer HTTP and stdio transports. This is how other
people’s agents can use Hundi, which is the legacy move.

