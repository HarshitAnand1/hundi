// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AcceptanceRegistry} from "../src/AcceptanceRegistry.sol";
import {ReceivableFactory} from "../src/ReceivableFactory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {MockUSDCe} from "../test/mocks/MockUSDCe.sol";

/// @notice Deploys registry, factory and pool; writes deployments/<chainId>.json.
/// @dev Env:
///   USDCE_ADDRESS      settlement token, copied from official HSK token docs [VERIFY]. Required unless
///                      DEPLOY_MOCK_TOKEN=true, which is only allowed on testnet (chain 133) and is labelled.
///   GUARDIAN_ADDRESS, UNDERWRITER_ADDRESS  default to the broadcaster.
///   Pool bounds: MAX_ADVANCE_BPS, MIN_FEE_BPS, MAX_TENOR_DAYS, BUYER_CAP, SELLER_CAP (token base units).
/// Usage: forge script script/Deploy.s.sol --rpc-url hsk_testnet --broadcast --private-key $DEPLOYER_PRIVATE_KEY
contract Deploy is Script {
    uint256 internal constant HSK_TESTNET = 133; // [VERIFY] against https://hskchain.net/docs

    function run() external {
        bool mock = vm.envOr("DEPLOY_MOCK_TOKEN", false);
        if (mock) require(block.chainid == HSK_TESTNET || block.chainid == 31337, "mock token only on testnet/local");

        vm.startBroadcast();
        address sender = msg.sender;
        address token = mock ? address(new MockUSDCe()) : vm.envAddress("USDCE_ADDRESS");
        address guardian = vm.envOr("GUARDIAN_ADDRESS", sender);
        address underwriter = vm.envOr("UNDERWRITER_ADDRESS", sender);

        LiquidityPool.Params memory p = LiquidityPool.Params({
            maxAdvanceBps: uint16(vm.envOr("MAX_ADVANCE_BPS", uint256(9000))),
            minFeeBps: uint16(vm.envOr("MIN_FEE_BPS", uint256(500))),
            maxTenorSeconds: uint64(vm.envOr("MAX_TENOR_DAYS", uint256(120)) * 1 days),
            buyerCap: vm.envOr("BUYER_CAP", uint256(50_000e6)),
            sellerCap: vm.envOr("SELLER_CAP", uint256(50_000e6))
        });

        AcceptanceRegistry registry = new AcceptanceRegistry();
        ReceivableFactory factory = new ReceivableFactory(registry, token);
        LiquidityPool pool = new LiquidityPool(IERC20(token), registry, factory, guardian, underwriter, p);
        vm.stopBroadcast();

        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeUint(k, "deployedAtBlock", block.number);
        vm.serializeAddress(k, "token", token);
        vm.serializeBool(k, "tokenIsMock", mock);
        vm.serializeAddress(k, "acceptanceRegistry", address(registry));
        vm.serializeAddress(k, "receivableFactory", address(factory));
        vm.serializeAddress(k, "vaultImplementation", factory.implementation());
        vm.serializeAddress(k, "liquidityPool", address(pool));
        vm.serializeAddress(k, "guardian", guardian);
        string memory json = vm.serializeAddress(k, "underwriter", underwriter);
        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);

        console2.log("token", token, mock ? "(MOCK - testnet only)" : "");
        console2.log("registry", address(registry));
        console2.log("factory", address(factory));
        console2.log("pool", address(pool));
        console2.log("written", path);
    }
}
