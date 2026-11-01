// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HundiBase} from "./utils/HundiBase.sol";
import {ReceivableVault} from "../src/ReceivableVault.sol";
import {ReceivableFactory} from "../src/ReceivableFactory.sol";
import {AcceptanceRegistry} from "../src/AcceptanceRegistry.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {Terms, Acceptance, HundiLib} from "../src/Types.sol";
import {ReentrantToken} from "./mocks/ReentrantToken.sol";

contract ReceivableVaultTest is HundiBase {
    // ---------------------------------------------------------------- worked example (HANDOFF 5.4)

    function test_worked_example_funding() public {
        (ReceivableVault v,) = _fundDefault();
        assertEq(usdc.balanceOf(seller), 8_820 * USDC, "seller receives advance - bond");
        assertEq(v.bondHeld(), 180 * USDC, "bond held");
        assertEq(v.advance(), 9_000 * USDC);
        assertEq(v.lenderDueAtMaturity(), 9_144 * USDC, "advance + 144 fee");
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Funded));
        assertEq(usdc.balanceOf(address(v)), 180 * USDC);
    }

    function test_worked_example_on_time_settlement() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        uint256 poolBefore = usdc.balanceOf(address(pool));
        vm.warp(t.dueDate);
        _pay(address(v), FACE);

        vm.expectEmit(address(v));
        emit ReceivableVault.Settled(9_144 * USDC, 10 * USDC, 1_026 * USDC, 0);
        v.settle();

        assertEq(usdc.balanceOf(address(pool)) - poolBefore, 9_144 * USDC, "lender due");
        assertEq(usdc.balanceOf(treasury), 10 * USDC, "protocol fee");
        assertEq(usdc.balanceOf(seller), 9_846 * USDC, "seller total 8,820 + 846 + 180");
        assertEq(usdc.balanceOf(address(v)), 0);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Settled));
        // 9,846 + 144 + 10 = 10,000
        assertEq(usdc.balanceOf(seller) + 144 * USDC + usdc.balanceOf(treasury), FACE);
    }

    function test_pool_share_price_rises_after_settlement() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        assertEq(pool.totalAssets(), POOL_LIQUIDITY);
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle(); // vault notifies pool via onVaultUpdate
        assertEq(pool.totalOutstanding(), 0);
        assertEq(pool.totalAssets(), POOL_LIQUIDITY + 144 * USDC);
        assertEq(pool.buyerExposure(buyer), 0);
    }

    // ---------------------------------------------------------------- late, partial, over

    function test_late_payment_accrues_late_interest_to_lender() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.graceSeconds + 10 days);
        uint256 late = uint256(9_000 * USDC) * 1800 * 10 days / (10_000 * 365 days);
        assertEq(v.amountDue(), 9_144 * USDC + late);

        uint256 poolBefore = usdc.balanceOf(address(pool));
        _pay(address(v), FACE);
        v.settle();
        assertEq(usdc.balanceOf(address(pool)) - poolBefore, 9_144 * USDC + late);
        assertEq(usdc.balanceOf(treasury), 10 * USDC, "late interest paid ahead of protocol fee");
        assertEq(usdc.balanceOf(seller), 8_820 * USDC + 846 * USDC - late + 180 * USDC);
    }

    function test_no_late_interest_within_grace() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.graceSeconds);
        assertEq(v.amountDue(), 9_144 * USDC);
    }

    function test_partial_payment_goes_to_lender_first() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), 5_000 * USDC);
        v.settle();
        assertEq(v.lenderPaid(), 5_000 * USDC);
        assertEq(v.protocolPaid(), 0);
        assertEq(v.sellerPaid(), 0);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Funded));
        assertEq(v.bondHeld(), 180 * USDC, "bond still held");

        _pay(address(v), 5_000 * USDC);
        v.settle();
        assertEq(v.lenderPaid(), 9_144 * USDC);
        assertEq(v.protocolPaid(), 10 * USDC);
        assertEq(v.sellerPaid(), 1_026 * USDC);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Settled));
    }

    function test_partial_payment_less_than_protocol_fee_after_lender() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), 9_144 * USDC + 4 * USDC);
        v.settle();
        assertEq(v.protocolPaid(), 4 * USDC);
        assertEq(v.sellerPaid(), 0);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Funded));
    }

    function test_overpayment_goes_to_seller() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), FACE + 500 * USDC);
        v.settle();
        assertEq(usdc.balanceOf(seller), 9_846 * USDC + 500 * USDC);
    }

    function test_dust_after_settlement_goes_to_seller() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();
        _pay(address(v), 7);
        v.settle();
        assertEq(usdc.balanceOf(seller), 9_846 * USDC + 7);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Settled));
    }

    function test_settle_is_idempotent() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();
        uint256 l = v.lenderPaid();
        uint256 s = usdc.balanceOf(seller);
        v.settle();
        v.settle();
        assertEq(v.lenderPaid(), l);
        assertEq(usdc.balanceOf(seller), s);
    }

    function test_settle_with_nothing_pending_is_noop() public {
        (ReceivableVault v,) = _fundDefault();
        v.settle();
        assertEq(v.lenderPaid(), 0);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Funded));
    }

    // ---------------------------------------------------------------- default

    function test_declare_default_forfeits_bond_to_lender() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.defaultSeconds + 1);
        uint256 due = v.lenderDue();
        uint256 poolBefore = usdc.balanceOf(address(pool));

        vm.expectEmit(address(v));
        emit ReceivableVault.BondForfeited(180 * USDC, 0);
        v.declareDefault();

        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Defaulted));
        assertEq(v.lenderDueFrozen(), due);
        assertEq(usdc.balanceOf(address(pool)) - poolBefore, 180 * USDC);
        assertEq(v.bondHeld(), 0);
        assertEq(pool.totalOutstanding(), 0, "principal written off");
        assertEq(pool.totalAssets(), POOL_LIQUIDITY - 9_000 * USDC + 180 * USDC);
    }

    function test_revert_default_too_early() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.defaultSeconds);
        vm.expectRevert(ReceivableVault.TooEarly.selector);
        v.declareDefault();
    }

    function test_default_with_pending_full_payment_settles_instead() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.defaultSeconds + 1);
        _pay(address(v), FACE);
        v.declareDefault();
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Settled));
    }

    function test_recovery_after_default_still_lender_first() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(uint256(t.dueDate) + t.defaultSeconds + 1);
        v.declareDefault();
        uint256 frozen = v.lenderDueFrozen();

        vm.warp(block.timestamp + 60 days); // no further late interest after default
        _pay(address(v), FACE);
        v.settle();
        assertEq(v.lenderPaid(), frozen);
        assertEq(v.protocolPaid(), 10 * USDC);
        assertEq(v.sellerPaid(), FACE + 180 * USDC - frozen - 10 * USDC);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Defaulted), "monotonic");
    }

    function test_revert_default_after_settled() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();
        vm.warp(uint256(t.dueDate) + t.defaultSeconds + 1);
        vm.expectRevert(abi.encodeWithSelector(ReceivableVault.BadState.selector, ReceivableVault.State.Settled));
        v.declareDefault();
    }

    // ---------------------------------------------------------------- open / prepaid / cancel

    function _acceptAndCreate(string memory n) internal returns (ReceivableVault v, Terms memory t) {
        t = _terms(n);
        Acceptance memory a = _acceptance(t, n, 1);
        registry.accept(a, _sign(buyerKey, a));
        v = ReceivableVault(factory.createVault(t));
    }

    function test_prepaid_open_vault_pays_seller_and_cannot_be_funded() public {
        (ReceivableVault v, Terms memory t) = _acceptAndCreate("INV-1");
        _pay(address(v), FACE);
        v.settle();
        assertEq(usdc.balanceOf(seller), FACE);
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Settled));

        Acceptance memory a = _acceptance(t, "INV-1", 1);
        vm.prank(underwriter);
        vm.expectRevert(abi.encodeWithSelector(ReceivableVault.BadState.selector, ReceivableVault.State.Settled));
        pool.advance(t, a, "");
    }

    function test_revert_fund_when_unsettled_prepayment_present() public {
        (ReceivableVault v, Terms memory t) = _acceptAndCreate("INV-1");
        _pay(address(v), FACE);
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        vm.prank(underwriter);
        vm.expectRevert(ReceivableVault.AlreadyPaid.selector);
        pool.advance(t, a, "");
    }

    /// @dev Unsolicited dust before funding must not block financing; it flows through the waterfall later.
    function test_dust_before_funding_does_not_grief() public {
        (ReceivableVault v, Terms memory t) = _acceptAndCreate("INV-1");
        _pay(address(v), 1);
        v.settle(); // no-op while Open and below face
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Open));

        Acceptance memory a = _acceptance(t, "INV-1", 1);
        vm.prank(underwriter);
        pool.advance(t, a, "");
        vm.warp(t.dueDate);
        _pay(address(v), FACE);
        v.settle();
        assertEq(usdc.balanceOf(seller), 9_846 * USDC + 1);
    }

    function test_cancel_after_funding_deadline() public {
        (ReceivableVault v, Terms memory t) = _acceptAndCreate("INV-1");
        vm.expectRevert(ReceivableVault.TooEarly.selector);
        v.cancel();

        vm.warp(v.fundingDeadline() + 1);
        v.cancel();
        assertEq(uint256(v.state()), uint256(ReceivableVault.State.Cancelled));

        Acceptance memory a = _acceptance(t, "INV-1", 1);
        vm.prank(underwriter);
        vm.expectRevert(abi.encodeWithSelector(ReceivableVault.BadState.selector, ReceivableVault.State.Cancelled));
        pool.advance(t, a, "");

        _pay(address(v), FACE); // buyer pays a cancelled vault anyway: all to seller
        v.settle();
        assertEq(usdc.balanceOf(seller), FACE);
    }

    function test_revert_fund_after_deadline() public {
        (ReceivableVault v, Terms memory t) = _acceptAndCreate("INV-1");
        vm.warp(v.fundingDeadline() + 1);
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        vm.prank(underwriter);
        vm.expectRevert(ReceivableVault.FundingClosed.selector);
        pool.advance(t, a, "");
    }

    function test_revert_fund_not_pool() public {
        (ReceivableVault v,) = _acceptAndCreate("INV-1");
        vm.expectRevert(ReceivableVault.NotPool.selector);
        v.fund(address(this), 1);
    }

    function test_revert_fund_above_advance_rate() public {
        (ReceivableVault v,) = _acceptAndCreate("INV-1");
        vm.prank(address(pool));
        vm.expectRevert(ReceivableVault.InvalidAdvance.selector);
        v.fund(address(pool), 9_000 * USDC + 1);
    }

    // ---------------------------------------------------------------- pull fallback (invariant 8)

    function test_blocklisted_seller_does_not_block_lender() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        usdc.setBlocked(seller, true);
        uint256 poolBefore = usdc.balanceOf(address(pool));
        _pay(address(v), FACE);
        v.settle();

        assertEq(usdc.balanceOf(address(pool)) - poolBefore, 9_144 * USDC, "lender still paid");
        assertEq(usdc.balanceOf(treasury), 10 * USDC, "protocol still paid");
        assertEq(v.owed(seller), 1_026 * USDC);
        assertEq(v.totalClaimable(), 1_026 * USDC);
        assertEq(usdc.balanceOf(address(v)), 1_026 * USDC);

        vm.expectRevert();
        v.claim(seller); // still blocked

        usdc.setBlocked(seller, false);
        v.claim(seller);
        assertEq(usdc.balanceOf(seller), 9_846 * USDC);
        assertEq(v.totalClaimable(), 0);
    }

    function test_blocklisted_treasury_does_not_block_seller() public {
        (ReceivableVault v, Terms memory t) = _fundDefault();
        vm.warp(t.dueDate);
        usdc.setBlocked(treasury, true);
        _pay(address(v), FACE);
        v.settle();
        assertEq(usdc.balanceOf(seller), 9_846 * USDC);
        assertEq(v.owed(treasury), 10 * USDC);
    }

    function test_revert_claim_nothing() public {
        (ReceivableVault v,) = _fundDefault();
        vm.expectRevert(ReceivableVault.NothingToClaim.selector);
        v.claim(seller);
    }

    // ---------------------------------------------------------------- hostile token

    function test_reentrancy_into_settle_is_blocked() public {
        ReentrantToken hostile = new ReentrantToken();
        ReceivableFactory f2 = new ReceivableFactory(registry, address(hostile));
        LiquidityPool p2 = new LiquidityPool(hostile, registry, f2, guardian, underwriter, _params());
        hostile.mint(lp, POOL_LIQUIDITY);
        vm.startPrank(lp);
        hostile.approve(address(p2), type(uint256).max);
        p2.deposit(POOL_LIQUIDITY, lp);
        vm.stopPrank();

        Terms memory t = _terms("INV-H");
        t.token = address(hostile);
        t.pool = address(p2);
        Acceptance memory a = Acceptance({
            buyer: buyer,
            seller: seller,
            token: address(hostile),
            faceAmount: FACE,
            dueDate: t.dueDate,
            invoiceHash: t.invoiceHash,
            invoiceNumberHash: keccak256("INV-H"),
            termsHash: HundiLib.hashTerms(t),
            vault: f2.predictVault(t),
            nonce: 77,
            expiry: uint64(block.timestamp + 1 days)
        });
        bytes memory sig = _sign(buyerKey, a);
        vm.prank(underwriter);
        ReceivableVault v = ReceivableVault(p2.advance(t, a, sig));

        hostile.setTarget(address(v));
        vm.warp(t.dueDate);
        hostile.mint(address(v), FACE);
        v.settle();
        assertTrue(hostile.reentered(), "attack attempted");
        assertFalse(hostile.reentrySucceeded(), "attack blocked by nonReentrant");
        assertEq(v.lenderPaid(), 9_144 * USDC);
    }

    // ---------------------------------------------------------------- fuzz: waterfall

    struct FuzzIn {
        uint256 face;
        uint16 advBps;
        uint16 feeBps;
        uint16 bondBps;
        uint16 protoBps;
        uint256 delay;
        uint256 paid;
    }

    function _fuzzVault(FuzzIn memory f) internal returns (ReceivableVault v, Terms memory t) {
        t = _terms("FZ");
        t.faceAmount = f.face;
        t.advanceBps = f.advBps;
        t.feeAnnualBps = f.feeBps;
        t.bondBps = f.bondBps;
        t.protocolFeeBps = f.protoBps;
        t.defaultSeconds = 365 days;
        v = _advance(t, "FZ", 1);
    }

    /// @dev Sum of payouts equals funds in; lender is never short while seller is paid; bounded by due.
    function testFuzz_waterfall_conserves_and_pays_lender_first(
        uint256 face,
        uint16 advBps,
        uint16 feeBps,
        uint16 bondBps,
        uint16 protoBps,
        uint256 delay,
        uint256 paid
    ) public {
        FuzzIn memory f;
        f.face = bound(face, 100 * USDC, 50_000 * USDC);
        f.advBps = uint16(bound(advBps, 1000, 9000));
        f.feeBps = uint16(bound(feeBps, 500, 5000));
        f.bondBps = uint16(bound(bondBps, 0, 2000));
        f.protoBps = uint16(bound(protoBps, 0, 100));
        f.delay = bound(delay, 0, 200 days);
        f.paid = bound(paid, 0, f.face * 2);
        (ReceivableVault v, Terms memory t) = _fuzzVault(f);

        uint256 bond = HundiLib.bondOf(t);
        assertEq(usdc.balanceOf(seller), HundiLib.advanceOf(t) - bond);

        vm.warp(uint256(t.dueDate) + f.delay);
        uint256 due = v.lenderDue();
        _pay(address(v), f.paid);
        v.settle();

        bool settled = v.state() == ReceivableVault.State.Settled;
        assertEq(v.lenderPaid() + v.protocolPaid() + v.sellerPaid(), settled ? f.paid + bond : f.paid, "conservation");
        assertEq(usdc.balanceOf(address(v)), v.bondHeld() + v.totalClaimable(), "nothing unaccounted");
        assertLe(v.lenderPaid(), due, "lender never overpaid");
        if (v.sellerPaid() > 0) assertEq(v.lenderPaid(), due, "lender first");
        if (v.protocolPaid() > 0) assertEq(v.lenderPaid(), due, "lender before protocol");
        assertEq(settled, f.paid >= due + HundiLib.protocolFeeOf(t));
    }
}
