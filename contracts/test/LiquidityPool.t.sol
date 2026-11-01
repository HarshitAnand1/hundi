// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HundiBase} from "./utils/HundiBase.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {ReceivableVault} from "../src/ReceivableVault.sol";
import {AcceptanceRegistry} from "../src/AcceptanceRegistry.sol";
import {Terms, Acceptance} from "../src/Types.sol";

contract LiquidityPoolTest is HundiBase {
    function _expectAdvanceRevert(Terms memory t, bytes4 sel) internal {
        Acceptance memory a = _acceptance(t, "INV-X", 9);
        bytes memory sig = _sign(buyerKey, a);
        vm.prank(underwriter);
        vm.expectRevert(sel);
        pool.advance(t, a, sig);
    }

    function test_advance_emits_and_tracks_exposure() public {
        (ReceivableVault v,) = _fundDefault();
        assertEq(pool.totalOutstanding(), 9_000 * USDC);
        assertEq(pool.buyerExposure(buyer), 9_000 * USDC);
        assertEq(pool.sellerExposure(seller), 9_000 * USDC);
        assertEq(pool.idle(), POOL_LIQUIDITY - 9_000 * USDC);
        assertEq(pool.totalAssets(), POOL_LIQUIDITY, "par accounting");
        assertEq(v.lender(), address(pool));
    }

    function test_revert_not_underwriter() public {
        Terms memory t = _terms("INV-X");
        Acceptance memory a = _acceptance(t, "INV-X", 9);
        bytes memory sig = _sign(buyerKey, a);
        vm.expectRevert(LiquidityPool.NotUnderwriter.selector);
        pool.advance(t, a, sig);
    }

    /// @dev Invariant 2: the same terms can never be financed twice.
    function test_revert_double_financing_same_terms() public {
        (, Terms memory t) = _fundDefault();
        _expectAdvanceRevert(t, LiquidityPool.AlreadyFunded.selector);
    }

    /// @dev Invariant 2: the same invoice number with new terms is blocked at the registry.
    function test_revert_double_financing_same_invoice_new_terms() public {
        _fundDefault(); // INV-001
        Terms memory t = _terms("INV-001");
        t.dueDate += 1 days;
        Acceptance memory a = _acceptance(t, "INV-001", 2);
        bytes memory sig = _sign(buyerKey, a);
        vm.prank(underwriter);
        vm.expectRevert(AcceptanceRegistry.DuplicateInvoice.selector);
        pool.advance(t, a, sig);
    }

    function test_revert_advance_bps_above_bound() public {
        Terms memory t = _terms("INV-X");
        t.advanceBps = 9001;
        _expectAdvanceRevert(t, LiquidityPool.AdvanceTooHigh.selector);
    }

    function test_revert_fee_below_bound() public {
        Terms memory t = _terms("INV-X");
        t.feeAnnualBps = 499;
        _expectAdvanceRevert(t, LiquidityPool.FeeTooLow.selector);
    }

    function test_revert_tenor_too_long() public {
        Terms memory t = _terms("INV-X");
        t.dueDate = uint64(block.timestamp + 121 days);
        _expectAdvanceRevert(t, LiquidityPool.TenorOutOfRange.selector);
    }

    function test_revert_due_in_past() public {
        Terms memory t = _terms("INV-X");
        t.dueDate = uint64(block.timestamp);
        _expectAdvanceRevert(t, LiquidityPool.TenorOutOfRange.selector);
    }

    function test_revert_wrong_pool_in_terms() public {
        Terms memory t = _terms("INV-X");
        t.pool = makeAddr("otherPool");
        _expectAdvanceRevert(t, LiquidityPool.WrongPool.selector);
    }

    function test_revert_wrong_token_in_terms() public {
        Terms memory t = _terms("INV-X");
        t.token = makeAddr("USDT");
        _expectAdvanceRevert(t, LiquidityPool.WrongToken.selector);
    }

    function test_revert_terms_hash_mismatch() public {
        Terms memory t = _terms("INV-X");
        Acceptance memory a = _acceptance(_terms("INV-OTHER"), "INV-X", 9);
        bytes memory sig = _sign(buyerKey, a);
        vm.prank(underwriter);
        vm.expectRevert(LiquidityPool.TermsHashMismatch.selector);
        pool.advance(t, a, sig);
    }

    /// @dev Invariant 4: per-buyer exposure cap.
    function test_revert_buyer_cap() public {
        for (uint256 i; i < 5; i++) {
            string memory n = string.concat("INV-B", vm.toString(i));
            Terms memory t = _terms(n);
            t.seller = i % 2 == 0 ? seller : makeAddr(n); // spread sellers so only the buyer cap binds
            _advance(t, n, 100 + i);
        }
        assertEq(pool.buyerExposure(buyer), 45_000 * USDC);
        Terms memory t6 = _terms("INV-B5");
        t6.seller = makeAddr("seller6");
        _expectAdvanceRevert(t6, LiquidityPool.BuyerCapExceeded.selector);
    }

    /// @dev Invariant 4: per-seller exposure cap.
    function test_revert_seller_cap() public {
        for (uint256 i; i < 5; i++) {
            string memory n = string.concat("INV-S", vm.toString(i));
            Terms memory t = _terms(n);
            (address b, uint256 k) = makeAddrAndKey(n);
            t.buyer = b;
            Acceptance memory a = _acceptance(t, n, 1);
            bytes memory sig = _sign(k, a);
            vm.prank(underwriter);
            pool.advance(t, a, sig);
        }
        Terms memory t6 = _terms("INV-S5");
        (address b6, uint256 k6) = makeAddrAndKey("b6");
        t6.buyer = b6;
        Acceptance memory a6 = _acceptance(t6, "INV-S5", 1);
        bytes memory sig6 = _sign(k6, a6);
        vm.prank(underwriter);
        vm.expectRevert(LiquidityPool.SellerCapExceeded.selector);
        pool.advance(t6, a6, sig6);
    }

    function test_revert_insufficient_liquidity() public {
        vm.prank(lp);
        pool.withdraw(95_000 * USDC, lp, lp);
        _expectAdvanceRevert(_terms("INV-X"), LiquidityPool.InsufficientLiquidity.selector);
    }

    function test_guardian_pause_blocks_only_new_advances() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.prank(guardian);
        pool.setPaused(true);
        _expectAdvanceRevert(_terms("INV-X"), LiquidityPool.AdvancesPaused.selector);

        // settlement and withdrawals still work while paused
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();
        vm.prank(lp);
        pool.withdraw(1_000 * USDC, lp, lp);
        assertEq(usdc.balanceOf(lp), 1_000 * USDC);
    }

    function test_revert_pause_not_guardian() public {
        vm.expectRevert(LiquidityPool.NotGuardian.selector);
        pool.setPaused(true);
    }

    function test_withdraw_limited_to_idle() public {
        _fundDefault();
        assertEq(pool.maxWithdraw(lp), POOL_LIQUIDITY - 9_000 * USDC);
        vm.prank(lp);
        vm.expectRevert();
        pool.withdraw(POOL_LIQUIDITY, lp, lp);
    }

    function test_sync_is_permissionless_and_idempotent() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), 4_000 * USDC);
        v.settle();
        assertEq(pool.totalOutstanding(), 5_000 * USDC, "principal-first reduction");
        vm.prank(makeAddr("anyone"));
        pool.sync(address(v));
        assertEq(pool.totalOutstanding(), 5_000 * USDC);
    }

    function test_revert_sync_unknown_vault() public {
        vm.expectRevert(LiquidityPool.UnknownVault.selector);
        pool.sync(makeAddr("random"));
    }

    function test_on_vault_update_from_stranger_is_noop() public {
        _fundDefault();
        vm.prank(makeAddr("stranger"));
        pool.onVaultUpdate();
        assertEq(pool.totalOutstanding(), 9_000 * USDC);
    }

    function test_second_depositor_gets_fair_shares_after_profit() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();

        address lp2 = makeAddr("lp2");
        usdc.mint(lp2, 10_000 * USDC);
        vm.startPrank(lp2);
        usdc.approve(address(pool), type(uint256).max);
        uint256 shares = pool.deposit(10_000 * USDC, lp2);
        vm.stopPrank();
        assertLt(shares, pool.balanceOf(lp) / 10, "late depositor does not capture earned fee");
        assertApproxEqAbs(pool.previewRedeem(shares), 10_000 * USDC, 1);
    }
}
