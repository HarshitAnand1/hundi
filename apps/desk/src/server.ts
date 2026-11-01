import { createServer, type ServerResponse } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT } from "./config.js";
import { Store, dataPath } from "./store.js";

/**
 * Read-only desk API + dashboard host. The scenario/keeper processes write the journal; this
 * server streams it. HSP webhooks are only accepted in gateway mode, which is not wired in L0.
 */
const PORT = Number(process.env.PORT ?? 8787);
const CHAIN_ID = Number(process.env.HSK_CHAIN_ID ?? 31337);
const WEB = join(REPO_ROOT, "apps/web/index.html");

const json = (res: ServerResponse, code: number, body: unknown) => {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(Store.serialize(body));
};

const agentCard = {
  name: "Hundi desk (seller agent)",
  description: "Issues buyer-accepted invoices on HashKey Chain and requests advances from the Hundi pool.",
  version: "0.1.0",
  capabilities: { streaming: true },
  skills: [
    { id: "issue_invoice", name: "Issue invoice", description: "Issue a signed hundi.invoice.v1 to a buyer agent" },
    { id: "request_advance", name: "Request advance", description: "Ask the pool to advance cash against an accepted invoice" },
  ],
};

createServer((req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    return res.end(readFileSync(WEB));
  }
  if (req.method === "GET" && url.pathname === "/.well-known/agent-card.json") return json(res, 200, agentCard);
  if (req.method === "GET" && url.pathname === "/api/state") {
    return json(res, 200, Store.readSnapshot(CHAIN_ID) ?? { chainId: CHAIN_ID, receivables: {}, events: [] });
  }
  if (req.method === "GET" && url.pathname === "/api/events") {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
    let sent = 0;
    const push = () => {
      const snap = Store.readSnapshot(CHAIN_ID);
      for (const ev of snap?.events.slice(sent) ?? []) res.write(`data: ${Store.serialize(ev)}\n\n`);
      sent = snap?.events.length ?? 0;
    };
    push();
    const timer = setInterval(push, 1000);
    req.on("close", () => clearInterval(timer));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/hsp/webhook") {
    // [VERIFY] HSP webhook signature scheme; refuse rather than trust unauthenticated payloads.
    return json(res, 501, { error: "HSP gateway mode not configured; self-relay mode has no webhook" });
  }
  json(res, 404, { error: "not found" });
}).listen(PORT, () => {
  console.log(`desk on http://localhost:${PORT}  chain ${CHAIN_ID}  journal ${existsSync(dataPath(CHAIN_ID)) ? dataPath(CHAIN_ID) : "(empty)"}`);
});
