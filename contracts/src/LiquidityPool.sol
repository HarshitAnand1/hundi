// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20, IERC20Metadata, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AcceptanceRegistry} from "./AcceptanceRegistry.sol";
import {ReceivableFactory} from "./ReceivableFactory.sol";
import {ReceivableVault, IVaultObserver} from "./ReceivableVault.sol";
import {Terms, Acceptance, HundiLib} from "./Types.sol";

/// @title LiquidityPool
/// @notice ERC-4626 pool of USDC.e that advances cash against accepted receivables within immutable bounds.
/// @dev The guardian can only pause new advances; it can never move funds or block withdrawals.
///      Fee income is recognised when received (conservative); outstanding principal is carried at par
///      and written off on default.
contract LiquidityPool is ERC4626, ReentrancyGuard, IVaultObserver {
    using SafeERC20 for IERC20;

    struct Params {
        uint16 maxAdvanceBps;
        uint16 minFeeBps;
        uint64 maxTenorSeconds;
        uint256 buyerCap;
        uint256 sellerCap;
    }

    struct Position {
        address buyer;
        address seller;
        uint256 principalOutstanding;
    }

    AcceptanceRegistry public immutable registry;
    ReceivableFactory public immutable factory;
    address public immutable guardian;
    /// @notice The only address allowed to request advances (the underwriter agent's key).
    address public immutable underwriter;
    uint16 public immutable maxAdvanceBps;
    uint16 public immutable minFeeBps;
    uint64 public immutable maxTenorSeconds;
    uint256 public immutable buyerCap;
    uint256 public immutable sellerCap;

    bool public paused;
    uint256 public totalOutstanding;
    mapping(address vault => Position) public positions;
    mapping(address => uint256) public buyerExposure;
    mapping(address => uint256) public sellerExposure;

    event Advanced(
        address indexed vault, bytes32 indexed termsHash, address indexed seller, address buyer, uint256 amount
    );
    event PositionSynced(address indexed vault, uint256 principalOutstanding, uint256 writtenOff);
    event Paused(bool paused);

    error NotGuardian();
    error NotUnderwriter();
    error AdvancesPaused();
    error WrongToken();
    error WrongPool();
    error TermsHashMismatch();
    error AdvanceTooHigh();
    error FeeTooLow();
    error TenorOutOfRange();
    error BuyerCapExceeded();
    error SellerCapExceeded();
    error InsufficientLiquidity();
    error UnknownVault();
    error AlreadyFunded();

    constructor(
        IERC20 asset_,
        AcceptanceRegistry registry_,
        ReceivableFactory factory_,
        address guardian_,
        address underwriter_,
        Params memory p
    ) ERC20("Hundi Pool Share", "hPOOL") ERC4626(asset_) {
        if (address(asset_) != factory_.token()) revert WrongToken();
        registry = registry_;
        factory = factory_;
        guardian = guardian_;
        underwriter = underwriter_;
        maxAdvanceBps = p.maxAdvanceBps;
        minFeeBps = p.minFeeBps;
        maxTenorSeconds = p.maxTenorSeconds;
        buyerCap = p.buyerCap;
        sellerCap = p.sellerCap;
    }

    // ---------------------------------------------------------------- advance

    /// @notice Record the acceptance (if needed), create the vault (if needed) and fund it.
    /// @param t Loan terms; must match the acceptance.
    /// @param a Buyer acceptance; ignored if already recorded in the registry.
    /// @param sig Buyer signature over `a`; ignored if already recorded.
    function advance(Terms calldata t, Acceptance calldata a, bytes calldata sig)
        external
        nonReentrant
        returns (address vault)
    {
        if (msg.sender != underwriter) revert NotUnderwriter();
        if (paused) revert AdvancesPaused();
        if (t.token != asset()) revert WrongToken();
        if (t.pool != address(this)) revert WrongPool();
        if (t.advanceBps > maxAdvanceBps) revert AdvanceTooHigh();
        if (t.feeAnnualBps < minFeeBps) revert FeeTooLow();
        if (t.dueDate <= block.timestamp || t.dueDate - block.timestamp > maxTenorSeconds) revert TenorOutOfRange();

        uint256 amount = HundiLib.advanceOf(t);
        if (buyerExposure[t.buyer] + amount > buyerCap) revert BuyerCapExceeded();
        if (sellerExposure[t.seller] + amount > sellerCap) revert SellerCapExceeded();
        if (amount > idle()) revert InsufficientLiquidity();

        bytes32 termsHash = HundiLib.hashTerms(t);
        vault = factory.predictVault(t);
        if (positions[vault].buyer != address(0)) revert AlreadyFunded();

        positions[vault] = Position(t.buyer, t.seller, amount);
        buyerExposure[t.buyer] += amount;
        sellerExposure[t.seller] += amount;
        totalOutstanding += amount;

        if (!registry.isAccepted(termsHash)) {
            if (a.termsHash != termsHash) revert TermsHashMismatch();
            registry.accept(a, sig);
        }
        if (vault.code.length == 0) factory.createVault(t);

        IERC20(asset()).forceApprove(vault, amount);
        ReceivableVault(vault).fund(address(this), amount);

        emit Advanced(vault, termsHash, t.seller, t.buyer, amount);
    }

    // ------------------------------------------------------------- accounting

    /// @notice Update outstanding principal for `vault` from its on-chain state. Permissionless.
    function sync(address vault) public {
        Position storage p = positions[vault];
        if (p.buyer == address(0)) revert UnknownVault();
        ReceivableVault v = ReceivableVault(vault);
        ReceivableVault.State s = v.state();

        uint256 next;
        uint256 writtenOff;
        if (s == ReceivableVault.State.Funded) {
            next = v.advance() - Math.min(v.lenderPaid(), v.advance());
        } else if (s == ReceivableVault.State.Defaulted) {
            // Remaining principal is written off; later recoveries arrive as idle cash.
            writtenOff = p.principalOutstanding;
        }
        if (next >= p.principalOutstanding) return;

        uint256 reduction = p.principalOutstanding - next;
        p.principalOutstanding = next;
        totalOutstanding -= reduction;
        buyerExposure[p.buyer] -= reduction;
        sellerExposure[p.seller] -= reduction;
        emit PositionSynced(vault, next, writtenOff);
    }

    /// @inheritdoc IVaultObserver
    function onVaultUpdate() external {
        if (positions[msg.sender].buyer != address(0)) sync(msg.sender);
    }

    /// @notice USDC.e held by the pool and available for advances or withdrawals.
    function idle() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function totalAssets() public view override returns (uint256) {
        return idle() + totalOutstanding;
    }

    /// @dev Withdrawals are limited to idle liquidity.
    function maxWithdraw(address owner) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(owner), idle());
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return Math.min(super.maxRedeem(owner), convertToShares(idle()));
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // --------------------------------------------------------------- guardian

    /// @notice Pause or resume new advances. Has no effect on deposits, withdrawals or settlement.
    function setPaused(bool paused_) external {
        if (msg.sender != guardian) revert NotGuardian();
        paused = paused_;
        emit Paused(paused_);
    }
}
