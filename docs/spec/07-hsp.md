> Extracted from docs/HANDOFF.md Section 7. Edit the handoff, not this file, or record changes in docs/DECISIONS.md.

## 7. HSP integration specification
What we know (from a competitor’s README and the official topic text; [VERIFY]
everything against official docs).

     HSP is AP2-aligned. The merchant creates a Cart Mandate (an order) and signs it; the
     payer’s wallet signs a Payment Mandate; HSP’s gateway verifies and executes the
     payment on-chain.
     Merchant API call to create orders: POST /api/v1/merchant/orders ; payer
     submission: POST /api/v1/payment/pay-mandate .
     Requests are HMAC-SHA256 signed; the cart carries an ES256K
      merchant_authorization signature; webhooks are signed and must be verified.
     For USDC.e the payer signs an EIP-3009 transferWithAuthorization ; HSP’s relayer
     submits it.
     The transfer is final: no escrow, refunds, splits or disputes at the HSP layer. All of that
     logic must live in our vault.

      pay_to can be a counterfactual contract address. A competitor’s design depends on
     this. Test it with a real small payment on day one.

Adapter modules ( packages/sdk/hsp ).

   Module                           Responsibility

    merchantClient                  Create orders, sign cart mandates, HMAC
                                    requests, fetch order status

    payerClient                     Build AP2 Payment Mandate, sign EIP-3009, submit
                                    to pay-mandate

    webhook                         Verify signature; idempotent processing keyed by
                                    flow or order ID

    reconcile                       Confirm on-chain: token, Transfer(buyer →
                                    vault, amount) , exact amount, confirmations

    rails                           Label settlement gateway or self-relayed from the
                                    funding tx sender

Modes. HSP_MODE=gateway uses real credentials. HSP_MODE=self-relay broadcasts the
buyer’s identical signed authorization ourselves, for testnet, forks and any time
credentials are missing. Both modes are valid; they must be labelled in the UI and in
PROOF.md.

If you do not get HSP credentials in time. Other teams reported the official SDK or
coordinator unreachable and built to the wire spec behind one interface. Do the same,
write an honest “HSP integration” section, keep asking the organisers, and switch to
gateway mode the moment access arrives.

Credentials checklist. Merchant app key and secret, ES256K merchant signing key and
public key registered with HSP, webhook URL (public HTTPS), supported token list, order
expiry rules, base URL. Keep all in .env , never in git.

