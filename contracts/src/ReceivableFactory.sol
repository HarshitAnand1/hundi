// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AcceptanceRegistry} from "./AcceptanceRegistry.sol";
import {ReceivableVault} from "./ReceivableVault.sol";
import {Terms, Acceptance, HundiLib} from "./Types.sol";

/// @title ReceivableFactory
/// @notice Deploys per-invoice vaults as CREATE2 clones with salt = termsHash, so the vault address
///         commits to every term. Creation is permissionless but requires a recorded acceptance.
contract ReceivableFactory {
    AcceptanceRegistry public immutable registry;
    address public immutable implementation;
    /// @notice The single settlement token (USDC.e). [VERIFY] address comes from deploy config.
    address public immutable token;

    mapping(address => bool) public isVault;

    event VaultCreated(address indexed vault, bytes32 indexed termsHash, address indexed buyer, address seller);

    error ZeroAddress();
    error TokenNotAllowed();
    error InvalidTerms();
    error NotAccepted();
    error AcceptanceMismatch();

    constructor(AcceptanceRegistry registry_, address token_) {
        if (address(registry_) == address(0) || token_ == address(0)) revert ZeroAddress();
        registry = registry_;
        token = token_;
        implementation = address(new ReceivableVault());
    }

    /// @notice The address the vault for `t` will have (whether or not it exists yet).
    function predictVault(Terms calldata t) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, HundiLib.hashTerms(t), address(this));
    }

    /// @notice Deploy and initialize the vault for `t`. Anyone may call; the result is the same whoever calls.
    function createVault(Terms calldata t) external returns (address vault) {
        _validate(t);
        bytes32 termsHash = HundiLib.hashTerms(t);
        Acceptance memory a = registry.acceptanceOf(termsHash);
        if (a.buyer == address(0)) revert NotAccepted();
        if (
            a.buyer != t.buyer || a.seller != t.seller || a.token != t.token || a.faceAmount != t.faceAmount
                || a.dueDate != t.dueDate || a.invoiceHash != t.invoiceHash || a.vault != predictVault(t)
        ) revert AcceptanceMismatch();

        vault = Clones.cloneDeterministic(implementation, termsHash);
        ReceivableVault(vault).initialize(t, a.expiry);
        isVault[vault] = true;
        emit VaultCreated(vault, termsHash, t.buyer, t.seller);
    }

    function _validate(Terms calldata t) internal view {
        if (t.token != token) revert TokenNotAllowed();
        if (
            t.seller == address(0) || t.buyer == address(0) || t.pool == address(0) || t.protocolTreasury == address(0)
        ) revert ZeroAddress();
        if (
            t.seller == t.buyer || t.faceAmount == 0 || t.advanceBps == 0 || t.advanceBps > HundiLib.BPS
                || t.bondBps > HundiLib.BPS || t.protocolFeeBps > HundiLib.BPS || t.defaultSeconds < t.graceSeconds
        ) revert InvalidTerms();
    }
}
