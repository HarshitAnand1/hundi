/**
 * L0 end-to-end on any chain with a deployments/<chainId>.json:
 *   happy path, duplicate invoice, payee swap, tampered cart. Prints every tx hash.
 * Usage: RPC_URL=... DEPLOYER_PRIVATE_KEY=... pnpm e2e   (or scripts/e2e-local.sh for anvil)
 */
import { connect } from "../apps/desk/src/chain.js";
import { deriveRoles, loadEnv } from "../apps/desk/src/config.js";
import { runScenario } from "../apps/desk/src/scenario.js";

const env = loadEnv();
const c = await connect(env.rpcUrl, env.expectedChainId);
const roles = deriveRoles(env.operatorKey);
console.log(`chain ${c.chain.id}  token ${c.deployment.token}${c.deployment.tokenIsMock ? " (MOCK)" : ""}  mode ${env.hspMode}`);
console.log(`buyer ${roles.buyer.address}  seller ${roles.seller.address}  operator ${roles.operator.address}`);

const rep = await runScenario(c, roles, env.face);
console.log(`\nreceivable ${rep.termsHash}\nvault      ${rep.vault}`);
for (const [k, h] of Object.entries(rep.txs)) console.log(`tx ${k.padEnd(16)} ${h}`);
console.log("\nattacks");
for (const a of rep.attacks) console.log(`  ${a.blocked ? "BLOCKED" : "MISSED "}  ${a.name}  [${a.codes.join(", ")}]`);
const s = rep.settled;
const e = rep.expected;
console.log(`\nwaterfall  lender ${s.lenderPaid} (expected ${e.lenderDue})  protocol ${s.protocolPaid} (expected ${e.protocolFee})  seller ${s.sellerPaid}`);
const ok = s.lenderPaid === e.lenderDue && s.protocolPaid === e.protocolFee && rep.attacks.every((a) => a.blocked);
console.log(ok ? "\nE2E PASS" : "\nE2E FAIL");
process.exit(ok ? 0 : 1);
