// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HundiBase} from "./utils/HundiBase.sol";
import {ReceivableVault} from "../src/ReceivableVault.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {ReceivableFactory} from "../src/ReceivableFactory.sol";
import {Terms, Acceptance, HundiLib} from "../src/Types.sol";
import {MockUSDCe} from "./mocks/MockUSDCe.sol";

/// @notice Random actor for the invariant suite. Records ghost state and flags rule breaks.
contract Handler is Test {
    MockUSDCe internal usdc;
    LiquidityPool internal pool;
    ReceivableVault[] public vaults;
    Terms[] internal termsList;
    Acceptance[] internal acceptances;
    address internal underwriter;
    address[] internal recipients;

    mapping(uint256 => uint256) public paidIn;
    mapping(uint256 => uint256) public initialBond;
    mapping(uint256 => ReceivableVault.State) public lastState;

    bool public lenderFirstViolated;
    bool public monotonicViolated;
    bool public doubleFundSucceeded;

    constructor(
        MockUSDCe usdc_,
        LiquidityPool pool_,
        address underwriter_,
        ReceivableVault[] memory vs,
        Terms[] memory ts,
        Acceptance[] memory as_
    ) {
        usdc = usdc_;
        pool = pool_;
        underwriter = underwriter_;
        for (uint256 i; i < vs.length; i++) {
            vaults.push(vs[i]);
            termsList.push(ts[i]);
            acceptances.push(as_[i]);
            initialBond[i] = vs[i].bondHeld();
            lastState[i] = vs[i].state();
            recipients.push(ts[i].seller);
        }
        recipients.push(ts[0].protocolTreasury);
    }

    function vaultCount() external view returns (uint256) {
        return vaults.length;
    }

    function pay(uint256 i, uint256 amount) external {
        i = bound(i, 0, vaults.length - 1);
        amount = bound(amount, 0, 15_000e6);
        usdc.mint(address(this), amount);
        usdc.transfer(address(vaults[i]), amount);
        paidIn[i] += amount;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 20 days));
    }

    function settle(uint256 i) external {
        i = bound(i, 0, vaults.length - 1);
        _guarded(i, true);
    }

    function declareDefault(uint256 i) external {
        i = bound(i, 0, vaults.length - 1);
        _guarded(i, false);
    }

    function toggleBlock(uint256 r) external {
        address who = recipients[bound(r, 0, recipients.length - 1)];
        usdc.setBlocked(who, !usdc.blocked(who));
    }

    function claim(uint256 i, uint256 r) external {
        i = bound(i, 0, vaults.length - 1);
        address who = recipients[bound(r, 0, recipients.length - 1)];
        try vaults[i].claim(who) {} catch {}
    }

    function refund(uint256 i) external {
        i = bound(i, 0, vaults.length - 1);
        vm.prank(underwriter);
        try pool.advance(termsList[i], acceptances[i], "") {
            doubleFundSucceeded = true;
        } catch {}
    }

    function _guarded(uint256 i, bool isSettle) internal {
        ReceivableVault v = vaults[i];
        uint256 dueBefore = v.lenderDue();
        uint256 protoBefore = v.protocolPaid();
        uint256 sellerBefore = v.sellerPaid();
        uint256 bondBefore = v.bondHeld();
        ReceivableVault.State sBefore = v.state();

        if (isSettle) {
            v.settle();
        } else {
            try v.declareDefault() {} catch {}
        }

        bool paidJunior = v.protocolPaid() > protoBefore
            || v.sellerPaid() > sellerBefore + (v.state() == ReceivableVault.State.Settled ? bondBefore : 0);
        // In Funded/Defaulted, money may go past the lender only once the lender is fully covered.
        if (
            paidJunior && (sBefore == ReceivableVault.State.Funded || sBefore == ReceivableVault.State.Defaulted)
                && v.lenderPaid() < (sBefore == ReceivableVault.State.Defaulted ? dueBefore : v.lenderDue())
        ) lenderFirstViolated = true;
        _checkMonotonic(i);
    }

    function _checkMonotonic(uint256 i) internal {
        ReceivableVault.State prev = lastState[i];
        ReceivableVault.State cur = vaults[i].state();
        if (prev != cur) {
            bool ok = prev == ReceivableVault.State.Funded
                && (cur == ReceivableVault.State.Settled || cur == ReceivableVault.State.Defaulted);
            if (!ok) monotonicViolated = true;
            lastState[i] = cur;
        }
    }
}

contract InvariantsTest is HundiBase {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        ReceivableVault[] memory vs = new ReceivableVault[](3);
        Terms[] memory ts = new Terms[](3);
        Acceptance[] memory as_ = new Acceptance[](3);
        for (uint256 i; i < 3; i++) {
            string memory n = string.concat("INV-INV-", vm.toString(i));
            ts[i] = _terms(n);
            ts[i].dueDate = uint64(block.timestamp + 20 days + i * 15 days);
            ts[i].bondBps = uint16(100 + i * 400);
            as_[i] = _acceptance(ts[i], n, 10 + i);
            bytes memory sig = _sign(buyerKey, as_[i]);
            vm.prank(underwriter);
            vs[i] = ReceivableVault(pool.advance(ts[i], as_[i], sig));
        }
        handler = new Handler(usdc, pool, underwriter, vs, ts, as_);
        targetContract(address(handler));
    }

    /// Invariant 1: tokens in == tokens out + tokens held (bond, claimable, unsettled).
    function invariant_conservation() public view {
        for (uint256 i; i < handler.vaultCount(); i++) {
            ReceivableVault v = handler.vaults(i);
            uint256 bal = usdc.balanceOf(address(v));
            // *Paid counters include amounts deferred to claim(), which are still in the vault.
            uint256 left = v.lenderPaid() + v.protocolPaid() + v.sellerPaid() - v.totalClaimable();
            assertEq(left + bal, handler.paidIn(i) + handler.initialBond(i), "conservation");
            assertEq(bal, v.pending() + v.bondHeld() + v.totalClaimable(), "balance decomposition");
        }
    }

    /// Invariant 2: a termsHash is funded at most once.
    function invariant_single_financing() public view {
        assertFalse(handler.doubleFundSucceeded());
    }

    /// Invariant 3: lender due is paid before protocol fee and seller residual.
    function invariant_lender_first() public view {
        assertFalse(handler.lenderFirstViolated());
    }

    /// Invariant 4: advances never exceed advanceBps x face or exposure caps.
    function invariant_bounded_advance() public view {
        for (uint256 i; i < handler.vaultCount(); i++) {
            ReceivableVault v = handler.vaults(i);
            assertLe(v.advance(), HundiLib.advanceOf(v.terms()));
            assertLe(v.lenderPaid(), v.lenderDue());
        }
        assertLe(pool.buyerExposure(buyer), _params().buyerCap);
        assertLe(pool.sellerExposure(seller), _params().sellerCap);
    }

    /// Invariant 7: no state moves backwards.
    function invariant_monotonic_state() public view {
        assertFalse(handler.monotonicViolated());
    }

    /// Pool accounting: totalOutstanding always equals the sum of open positions.
    function invariant_pool_outstanding_matches_positions() public view {
        uint256 sum;
        for (uint256 i; i < handler.vaultCount(); i++) {
            (,, uint256 p) = pool.positions(address(handler.vaults(i)));
            sum += p;
        }
        assertEq(pool.totalOutstanding(), sum);
    }
}
