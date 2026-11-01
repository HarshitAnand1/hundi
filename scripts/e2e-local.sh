#!/usr/bin/env bash
# Local anvil run with a MOCK token. Uses anvil's public well-known dev key #0 (not a secret).
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
PORT=${PORT:-8545}
anvil --port "$PORT" --silent &
ANVIL=$!
trap 'kill $ANVIL' EXIT
sleep 1
rm -f apps/desk/data/31337.json  # anvil restarts empty, so drop the old local journal
export RPC_URL="http://127.0.0.1:$PORT"
export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(cd contracts && DEPLOY_MOCK_TOKEN=true forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null)
pnpm exec tsx scripts/e2e.ts
