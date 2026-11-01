import { keccak256, toBytes, type Hex } from "viem";

/**
 * Deterministic JSON: object keys sorted, no whitespace, bigint as decimal string, undefined fields dropped.
 * Used for invoice and cart hashing. Not RFC 8785 for floats: amounts are integers by schema.
 */
export function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "bigint":
      return JSON.stringify(value.toString());
    case "number":
      if (!Number.isSafeInteger(value)) throw new Error("canonicalJson: only safe integers allowed");
      return JSON.stringify(value);
    case "string":
    case "boolean":
      return JSON.stringify(value);
    case "object": {
      if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
      const entries = Object.entries(value as Record<string, unknown>)
        .filter(([, v]) => v !== undefined)
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
      return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(",")}}`;
    }
    default:
      throw new Error(`canonicalJson: unsupported type ${typeof value}`);
  }
}

export function canonicalHash(value: unknown): Hex {
  return keccak256(toBytes(canonicalJson(value)));
}
