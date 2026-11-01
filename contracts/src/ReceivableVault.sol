// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Terms, HundiLib} from "./Types.sol";

/// @notice Optional callback on the lender (the pool) after money moves.
interface IVaultObserver {
    function onVaultUpdate() external;
}

/// @title ReceivableVault
/// @notice Per-invoice vault deployed at a CREATE2 address derived from its Terms. HSP pays the buyer's
///         settlement here; settle() pays the lender first, then the protocol fee, then the seller.
/// @dev State: Open -> Funded -> Settled | Defaulted; Open -> Cancelled; Open -> Settled (prepaid).
///      Not upgradeable. All money-moving functions except fund() are permissionless.
contract ReceivableVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum State {
        Open,
        Funded,
        Settled,
        Defaulted,
        Cancelled
    }

    Terms internal _terms;
    address public factory;
    uint64 public fundingDeadline;
    State public state;

    address public lender;
    uint256 public advance;
    uint256 public bondHeld;
    uint64 public fundedAt;
    uint64 public settledAt;
    /// @notice advance + discount fee to dueDate, fixed at funding.
    uint256 public lenderDueAtMaturity;
    /// @notice lender due frozen at default (includes late interest up to that moment).
    uint256 public lenderDueFrozen;

    uint256 public lenderPaid;
    uint256 public protocolPaid;
    uint256 public sellerPaid;

    /// @notice Pull-fallback balances for recipients whose push transfer failed.
    mapping(address => uint256) public owed;
    uint256 public totalClaimable;

    event Initialized(bytes32 indexed termsHash, uint64 fundingDeadline);
    event Funded(address indexed lender, uint256 advance, uint256 bond, uint256 sellerReceived, uint256 lenderDueAtMaturity);
    event Settled(uint256 lenderPaid, uint256 protocolPaid, uint256 sellerPaid, uint256 daysLate);
    event DefaultDeclared(uint256 lenderDue, uint256 shortfall);
    event BondForfeited(uint256 toLender, uint256 toSeller);
    event PaymentDeferred(address indexed to, uint256 amount);
    event Claimed(address indexed to, uint256 amount);
    event Cancelled();

    error AlreadyInitialized();
    error NotPool();
    error BadState(State current);
    error FundingClosed();
    error InvalidAdvance();
    error AlreadyPaid();
    error PastDue();
    error TooEarly();
    error NothingToClaim();

    constructor() {
        // Lock the implementation; clones start with empty storage.
        factory = address(this);
    }

    /// @notice Called once by the factory in the same transaction as the clone deployment.
    function initialize(Terms calldata t, uint64 fundingDeadline_) external {
        if (factory != address(0)) revert AlreadyInitialized();
        factory = msg.sender;
        _terms = t;
        fundingDeadline = fundingDeadline_;
        emit Initialized(HundiLib.hashTerms(t), fundingDeadline_);
    }

    // ---------------------------------------------------------------- funding

    /// @notice Pool advances `advance_` against this receivable. Seller receives advance - bond.
    /// @dev Pulls tokens from the pool, which must have approved this vault.
    function fund(address lender_, uint256 advance_) external nonReentrant {
        Terms memory t = _terms;
        if (msg.sender != t.pool) revert NotPool();
        if (state != State.Open) revert BadState(state);
        if (block.timestamp > fundingDeadline) revert FundingClosed();
        if (block.timestamp >= t.dueDate) revert PastDue();
        if (advance_ == 0 || advance_ > HundiLib.advanceOf(t)) revert InvalidAdvance();
        if (_pending() >= t.faceAmount) revert AlreadyPaid();

        uint256 bond = advance_ * t.bondBps / HundiLib.BPS;
        state = State.Funded;
        lender = lender_;
        advance = advance_;
        bondHeld = bond;
        fundedAt = uint64(block.timestamp);
        lenderDueAtMaturity = advance_ + HundiLib.interest(advance_, t.feeAnnualBps, t.dueDate - block.timestamp);

        IERC20 token = IERC20(t.token);
        token.safeTransferFrom(msg.sender, t.seller, advance_ - bond);
        token.safeTransferFrom(msg.sender, address(this), bond);

        emit Funded(lender_, advance_, bond, advance_ - bond, lenderDueAtMaturity);
    }

    /// @notice Cancel an unfunded vault after the acceptance (funding) deadline.
    function cancel() external {
        if (state != State.Open) revert BadState(state);
        if (block.timestamp <= fundingDeadline) revert TooEarly();
        state = State.Cancelled;
        emit Cancelled();
    }

    // ------------------------------------------------------------- settlement

    /// @notice Apply the waterfall to every unaccounted token in the vault. Permissionless, idempotent.
    function settle() external nonReentrant {
        _settle();
        _notify();
    }

    /// @notice Declare default after dueDate + defaultSeconds. Bond is forfeited to the lender up to the shortfall.
    function declareDefault() external nonReentrant {
        Terms memory t = _terms;
        if (state != State.Funded) revert BadState(state);
        if (block.timestamp <= uint256(t.dueDate) + t.defaultSeconds) revert TooEarly();

        _settle();
        if (state == State.Funded) {
            uint256 due = _lenderDue();
            uint256 shortfall = due - lenderPaid;
            uint256 toLender = Math.min(bondHeld, shortfall);
            uint256 toSeller = bondHeld - toLender;

            state = State.Defaulted;
            lenderDueFrozen = due;
            bondHeld = 0;
            lenderPaid += toLender;
            sellerPaid += toSeller;

            emit DefaultDeclared(due, shortfall);
            emit BondForfeited(toLender, toSeller);
            _push(lender, toLender);
            _push(t.seller, toSeller);
        }
        _notify();
    }

    /// @notice Pull fallback: pay out an amount whose push transfer failed earlier.
    function claim(address to) external nonReentrant {
        uint256 amount = owed[to];
        if (amount == 0) revert NothingToClaim();
        owed[to] = 0;
        totalClaimable -= amount;
        IERC20(_terms.token).safeTransfer(to, amount);
        emit Claimed(to, amount);
    }

    function _settle() internal {
        uint256 pending = _pending();
        if (pending == 0) return;
        Terms memory t = _terms;
        State s = state;

        if (s == State.Open) {
            // Prepaid before funding: the seller is paid in full and the vault can never be funded.
            if (pending < t.faceAmount) return;
            state = State.Settled;
            settledAt = uint64(block.timestamp);
            sellerPaid += pending;
            emit Settled(0, 0, pending, _daysLate(t));
            _push(t.seller, pending);
            return;
        }

        if (s == State.Settled || s == State.Cancelled) {
            // Overpayment, dust or late unsolicited transfers go to the seller.
            sellerPaid += pending;
            emit Settled(0, 0, pending, 0);
            _push(t.seller, pending);
            return;
        }

        // Funded or Defaulted: lender first, then protocol fee, then seller.
        uint256 lenderDue = s == State.Defaulted ? lenderDueFrozen : _lenderDue();
        uint256 toLender = Math.min(pending, lenderDue - lenderPaid);
        uint256 rest = pending - toLender;
        uint256 toProtocol = Math.min(rest, HundiLib.protocolFeeOf(t) - protocolPaid);
        uint256 toSeller = rest - toProtocol;

        lenderPaid += toLender;
        protocolPaid += toProtocol;

        if (s == State.Funded && lenderPaid == lenderDue && protocolPaid == HundiLib.protocolFeeOf(t)) {
            state = State.Settled;
            settledAt = uint64(block.timestamp);
            toSeller += bondHeld;
            bondHeld = 0;
        }
        sellerPaid += toSeller;

        emit Settled(toLender, toProtocol, toSeller, _daysLate(t));
        _push(lender, toLender);
        _push(t.protocolTreasury, toProtocol);
        _push(t.seller, toSeller);
    }

    function _push(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (!IERC20(_terms.token).trySafeTransfer(to, amount)) {
            owed[to] += amount;
            totalClaimable += amount;
            emit PaymentDeferred(to, amount);
        }
    }

    function _notify() internal {
        address l = lender;
        if (l != address(0) && l.code.length > 0) {
            try IVaultObserver(l).onVaultUpdate() {} catch {}
        }
    }

    // ------------------------------------------------------------------ views

    function _pending() internal view returns (uint256) {
        return IERC20(_terms.token).balanceOf(address(this)) - bondHeld - totalClaimable;
    }

    /// @dev Lender due at the current time while Funded: advance + fee + late interest.
    function _lenderDue() internal view returns (uint256) {
        uint256 lateStart = uint256(_terms.dueDate) + _terms.graceSeconds;
        uint256 late = block.timestamp > lateStart
            ? HundiLib.interest(advance, _terms.lateAnnualBps, block.timestamp - lateStart)
            : 0;
        return lenderDueAtMaturity + late;
    }

    function _daysLate(Terms memory t) internal view returns (uint256) {
        return block.timestamp > t.dueDate ? (block.timestamp - t.dueDate) / 1 days : 0;
    }

    /// @notice The immutable terms of this vault.
    function terms() external view returns (Terms memory) {
        return _terms;
    }

    /// @notice Total owed to the lender right now (including late interest), whether or not paid.
    function lenderDue() public view returns (uint256) {
        if (state == State.Funded) return _lenderDue();
        if (state == State.Defaulted) return lenderDueFrozen;
        return lenderPaid;
    }

    /// @notice Remaining amount owed to the lender at the current time.
    function amountDue() external view returns (uint256) {
        return lenderDue() - lenderPaid;
    }

    /// @notice Tokens in the vault not yet run through the waterfall.
    function pending() external view returns (uint256) {
        return _pending();
    }
}
