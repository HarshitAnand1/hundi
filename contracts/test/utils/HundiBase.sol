// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AcceptanceRegistry} from "../../src/AcceptanceRegistry.sol";
import {ReceivableFactory} from "../../src/ReceivableFactory.sol";
import {ReceivableVault} from "../../src/ReceivableVault.sol";
import {LiquidityPool} from "../../src/LiquidityPool.sol";
import {Terms, Acceptance, HundiLib} from "../../src/Types.sol";
import {MockUSDCe} from "../mocks/MockUSDCe.sol";

/// @notice Shared deployment and helpers. Numbers follow the HANDOFF 5.4 worked example.
abstract contract HundiBase is Test {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant FACE = 10_000 * USDC;
    uint256 internal constant POOL_LIQUIDITY = 100_000 * USDC;

    MockUSDCe internal usdc;
    AcceptanceRegistry internal registry;
    ReceivableFactory internal factory;
    LiquidityPool internal pool;

    address internal seller = makeAddr("seller");
    address internal buyer;
    uint256 internal buyerKey;
    address internal lp = makeAddr("lp");
    address internal guardian = makeAddr("guardian");
    address internal underwriter = makeAddr("underwriter");
    address internal treasury = makeAddr("treasury");
    address internal relayer = makeAddr("hspRelayer");

    function setUp() public virtual {
        vm.warp(1_790_000_000); // fixed start time for reproducible maths
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        usdc = new MockUSDCe();
        registry = new AcceptanceRegistry();
        factory = new ReceivableFactory(registry, address(usdc));
        pool = new LiquidityPool(usdc, registry, factory, guardian, underwriter, _params());

        usdc.mint(lp, POOL_LIQUIDITY);
        vm.startPrank(lp);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(POOL_LIQUIDITY, lp);
        vm.stopPrank();
    }

    function _params() internal pure virtual returns (LiquidityPool.Params memory) {
        return LiquidityPool.Params({
            maxAdvanceBps: 9000,
            minFeeBps: 500,
            maxTenorSeconds: 120 days,
            buyerCap: 50_000 * USDC,
            sellerCap: 50_000 * USDC
        });
    }

    function _terms(string memory invoiceNumber) internal view returns (Terms memory t) {
        t = Terms({
            seller: seller,
            buyer: buyer,
            token: address(usdc),
            faceAmount: FACE,
            dueDate: uint64(block.timestamp + 73 days),
            invoiceHash: keccak256(abi.encodePacked("invoice-json:", invoiceNumber)),
            advanceBps: 9000,
            feeAnnualBps: 800,
            lateAnnualBps: 1800,
            bondBps: 200,
            protocolFeeBps: 10,
            graceSeconds: 3 days,
            defaultSeconds: 30 days,
            pool: address(pool),
            protocolTreasury: treasury
        });
    }

    function _acceptance(Terms memory t, string memory invoiceNumber, uint256 nonce)
        internal
        view
        returns (Acceptance memory)
    {
        return Acceptance({
            buyer: t.buyer,
            seller: t.seller,
            token: t.token,
            faceAmount: t.faceAmount,
            dueDate: t.dueDate,
            invoiceHash: t.invoiceHash,
            invoiceNumberHash: keccak256(bytes(invoiceNumber)),
            termsHash: HundiLib.hashTerms(t),
            vault: factory.predictVault(t),
            nonce: nonce,
            expiry: uint64(block.timestamp + 7 days)
        });
    }

    function _sign(uint256 key, Acceptance memory a) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.digest(a));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Accept + create + fund in one call, as the underwriter.
    function _advance(Terms memory t, string memory invoiceNumber, uint256 nonce)
        internal
        returns (ReceivableVault vault)
    {
        Acceptance memory a = _acceptance(t, invoiceNumber, nonce);
        bytes memory sig = _sign(buyerKey, a);
        vm.prank(underwriter);
        vault = ReceivableVault(pool.advance(t, a, sig));
    }

    function _fundDefault() internal returns (ReceivableVault vault, Terms memory t) {
        t = _terms("INV-001");
        vault = _advance(t, "INV-001", 1);
    }

    /// @dev Simulates the HSP relayer's transfer of the buyer's funds into the vault.
    function _pay(address vault, uint256 amount) internal {
        usdc.mint(relayer, amount);
        vm.prank(relayer);
        usdc.transfer(vault, amount);
    }
}
