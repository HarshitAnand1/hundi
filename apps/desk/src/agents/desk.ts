import type { LocalAccount } from "viem";
import { signSelfRelayCart, type CartView } from "@hundi/sdk";
import type { Receivable } from "../store.js";

/**
 * Desk = merchant of record (honest limit: one merchant of record for all sellers).
 * In self-relay mode it signs Hundi's own cart format; in gateway mode HSP creates the order and
 * signs it with ES256K, and the adapter maps it into a CartView. [VERIFY] gateway wire format.
 */
export class Desk {
  constructor(readonly merchant: LocalAccount) {}

  order(r: Receivable, orderId: string): Promise<CartView> {
    return signSelfRelayCart(this.merchant, {
      orderId,
      payTo: r.vault,
      token: r.terms.token,
      amount: r.terms.faceAmount,
      termsHash: r.termsHash,
      dueDate: r.terms.dueDate,
    });
  }
}
