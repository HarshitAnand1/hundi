#!/usr/bin/env -S npx tsx
/**
 * Hundi MCP server (stdio). Lets any MCP-capable agent issue, accept, finance, pay and inspect
 * receivables on the chain named by RPC_URL. Env as for `pnpm e2e` (RPC_URL, DEPLOYER_PRIVATE_KEY).
 * Logs go to stderr; stdout is the MCP channel.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { zAddress, zHex32 } from "@hundi/sdk";
import { Store, connect, deriveRoles, loadEnv } from "@hundi/desk";
import { HundiTools } from "./tools.js";

const env = loadEnv();
const c = await connect(env.rpcUrl, env.expectedChainId);
const tools = new HundiTools(c, deriveRoles(env.operatorKey));
const server = new McpServer({ name: "hundi", version: "0.1.0" });

const reply = (x: unknown) => ({ content: [{ type: "text" as const, text: Store.serialize(x) }] });
const amount = z.string().regex(/^\d+$/).describe("Token base units (USDC.e has 6 decimals: 1000000 = 1 USDC.e)");

server.registerTool(
  "issue_invoice",
  {
    description: "Seller agent issues and signs a hundi.invoice.v1; a simulated logistics agent attests delivery. Also registers the matching purchase order in the demo buyer's book.",
    inputSchema: {
      invoiceNumber: z.string().min(1).max(64),
      amount,
      dueInDays: z.number().int().min(1).max(365),
      goods: z.string().min(1).max(500),
      poAmount: amount.optional().describe("PO amount if different from the invoice (to demo an inflated invoice)"),
      payTo: zAddress.optional().describe("Payout address if different from the seller (to demo a payee swap)"),
      notes: z.string().max(2000).optional(),
    },
  },
  async (a) =>
    reply(
      await tools.issueInvoice({
        invoiceNumber: a.invoiceNumber,
        amount: BigInt(a.amount),
        dueInDays: a.dueInDays,
        goods: a.goods,
        ...(a.poAmount ? { poAmount: BigInt(a.poAmount) } : {}),
        ...(a.payTo ? { payTo: a.payTo } : {}),
        ...(a.notes !== undefined ? { notes: a.notes } : {}),
      }),
    ),
);

server.registerTool(
  "accept_invoice",
  {
    description: "Buyer agent runs the deterministic verifyInvoice gate. Returns named refusal codes, or prices the terms and signs an EIP-712 acceptance naming the predicted vault.",
    inputSchema: { invoiceNumber: z.string(), humanApproved: z.boolean().optional().describe("Explicit human approval, needed at or above the threshold") },
  },
  async (a) => reply(await tools.acceptInvoice({ invoiceNumber: a.invoiceNumber, ...(a.humanApproved !== undefined ? { humanApproved: a.humanApproved } : {}) })),
);

server.registerTool(
  "request_advance",
  { description: "Pool advances against an accepted invoice: records the acceptance, creates the CREATE2 vault and pays the seller (on-chain).", inputSchema: { termsHash: zHex32 } },
  async (a) => reply(await tools.requestAdvance({ termsHash: a.termsHash })),
);

server.registerTool(
  "pay_invoice",
  { description: "Desk creates the order; buyer agent runs verifyCart and pays the vault (self-relay); keeper settles the lender-first waterfall.", inputSchema: { termsHash: zHex32 } },
  async (a) => reply(await tools.payInvoice({ termsHash: a.termsHash })),
);

server.registerTool(
  "get_receivable",
  { description: "On-chain state of one receivable: vault state, amounts paid to lender, protocol and seller, bond, tx hashes.", inputSchema: { termsHash: zHex32 } },
  async (a) => reply(await tools.getReceivable({ termsHash: a.termsHash })),
);

server.registerTool("list_receivables", { description: "All receivables financed through this desk." }, async () => reply(tools.listReceivables()));

await server.connect(new StdioServerTransport());
console.error(`hundi mcp ready on chain ${c.chain.id}`);
