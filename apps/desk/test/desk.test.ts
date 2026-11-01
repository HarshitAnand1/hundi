import { describe, expect, it } from "vitest";
import { keccak256, toBytes } from "viem";
import { deriveRoles, loadEnv } from "../src/config.js";
import { Store } from "../src/store.js";

const KEY = keccak256(toBytes("hundi-desk-test-operator"));

describe("desk config", () => {
  it("derives distinct, deterministic role wallets from the operator key", () => {
    const a = deriveRoles(KEY);
    const b = deriveRoles(KEY);
    const addrs = [a.operator, a.buyer, a.seller, a.logistics, a.merchant, a.attacker].map((x) => x.address);
    expect(new Set([...addrs, a.treasury]).size).toBe(7);
    expect(b.buyer.address).toBe(a.buyer.address);
  });

  it("rejects a malformed key without echoing it", () => {
    const bad = "0x1234";
    expect(() => loadEnv({ RPC_URL: "http://x", DEPLOYER_PRIVATE_KEY: bad })).toThrow(/value not shown/);
    try {
      loadEnv({ RPC_URL: "http://x", DEPLOYER_PRIVATE_KEY: bad });
    } catch (e) {
      expect(String(e)).not.toContain(bad);
    }
  });

  it("rejects an unknown HSP_MODE", () => {
    expect(() => loadEnv({ RPC_URL: "http://x", DEPLOYER_PRIVATE_KEY: KEY, HSP_MODE: "yolo" })).toThrow();
  });
});

describe("store serialisation", () => {
  it("round-trips bigints", () => {
    expect(Store.serialize({ a: 10_000_000_000n, b: "x" })).toBe('{"a":"10000000000n","b":"x"}');
  });
});
