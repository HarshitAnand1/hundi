import { verifyMessage, type Address, type Hex, type LocalAccount } from "viem";
import { canonicalHash } from "../canonical.js";
import type { CartView } from "../verifyCart.js";

/**
 * Cart hashing and merchant signing for HSP_MODE=self-relay ONLY.
 * This is Hundi's own scheme (canonical-JSON keccak + EIP-191), NOT HSP's ES256K merchant_authorization.
 * The gateway adapter must replace both functions with the official HSP ones. [VERIFY]
 */
export function selfRelayCartHash(cart: Omit<CartView, "cartHash" | "merchantSignature">): Hex {
  return canonicalHash({
    scheme: "hundi.selfrelay.cart.v1",
    orderId: cart.orderId,
    payTo: cart.payTo,
    token: cart.token,
    amount: cart.amount,
    termsHash: cart.termsHash.toLowerCase(),
    dueDate: cart.dueDate,
  });
}

export async function signSelfRelayCart(
  merchant: LocalAccount,
  cart: Omit<CartView, "cartHash" | "merchantSignature">,
): Promise<CartView> {
  const cartHash = selfRelayCartHash(cart);
  const merchantSignature = await merchant.signMessage({ message: { raw: cartHash } });
  return { ...cart, cartHash, merchantSignature };
}

export function selfRelayCartVerifier(merchant: Address) {
  return {
    computeCartHash: (c: CartView) => selfRelayCartHash(c),
    verifyMerchantSignature: async (c: CartView) => {
      try {
        return await verifyMessage({ address: merchant, message: { raw: c.cartHash }, signature: c.merchantSignature });
      } catch {
        return false;
      }
    },
  };
}
