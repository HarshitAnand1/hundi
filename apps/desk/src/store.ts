import { EventEmitter } from "node:events";
import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import type { Address, Hash, Hex } from "viem";
import type { Acceptance, Invoice, Terms } from "@hundi/sdk";
import { REPO_ROOT } from "./config.js";

export type EventKind =
  | "invoice.issued"
  | "delivery.attested"
  | "invoice.refused"
  | "invoice.accepted"
  | "advance.funded"
  | "order.created"
  | "cart.refused"
  | "payment.sent"
  | "vault.settled"
  | "attack.blocked"
  | "info";

export interface DeskEvent {
  at: number;
  kind: EventKind;
  termsHash?: Hex;
  summary: string;
  tx?: Hash;
  data?: Record<string, unknown>;
}

export interface Receivable {
  termsHash: Hex;
  invoice: Invoice;
  terms: Terms;
  acceptance: Acceptance;
  vault: Address;
  txs: Record<string, Hash>;
}

interface Snapshot {
  chainId: number;
  receivables: Record<string, Receivable>;
  events: DeskEvent[];
}

const replacer = (_k: string, v: unknown) => (typeof v === "bigint" ? `${v}n` : v);
const reviver = (_k: string, v: unknown) => (typeof v === "string" && /^-?\d+n$/.test(v) ? BigInt(v.slice(0, -1)) : v);

export const dataPath = (chainId: number) => join(REPO_ROOT, "apps/desk/data", `${chainId}.json`);

/** Small JSON-file journal (L0 stand-in for SQLite; see DECISIONS.md). Single writer per chain. */
export class Store extends EventEmitter {
  private snap: Snapshot;

  constructor(readonly chainId: number, private readonly path = dataPath(chainId)) {
    super();
    this.snap = existsSync(path)
      ? (JSON.parse(readFileSync(path, "utf8"), reviver) as Snapshot)
      : { chainId, receivables: {}, events: [] };
  }

  static readSnapshot(chainId: number): Snapshot | undefined {
    const p = dataPath(chainId);
    return existsSync(p) ? (JSON.parse(readFileSync(p, "utf8"), reviver) as Snapshot) : undefined;
  }

  static serialize(x: unknown): string {
    return JSON.stringify(x, replacer);
  }

  get receivables(): Receivable[] {
    return Object.values(this.snap.receivables);
  }

  get events(): DeskEvent[] {
    return this.snap.events;
  }

  getByTermsHash(h: Hex): Receivable | undefined {
    return this.snap.receivables[h.toLowerCase()];
  }

  hasInvoiceKey(key: Hex, keyOf: (r: Receivable) => Hex): boolean {
    return this.receivables.some((r) => keyOf(r).toLowerCase() === key.toLowerCase());
  }

  put(r: Receivable): void {
    this.snap.receivables[r.termsHash.toLowerCase()] = r;
    this.flush();
  }

  log(e: Omit<DeskEvent, "at">): DeskEvent {
    const ev = { at: Math.floor(Date.now() / 1000), ...e };
    this.snap.events.push(ev);
    this.flush();
    this.emit("event", ev);
    return ev;
  }

  private flush(): void {
    mkdirSync(dirname(this.path), { recursive: true });
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.snap, replacer, 2));
    renameSync(tmp, this.path);
  }
}
