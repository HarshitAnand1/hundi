// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Acceptance, HundiLib} from "./Types.sol";

/// @title AcceptanceRegistry
/// @notice Records buyer-signed acceptances (EIP-712, ECDSA or ERC-1271) and blocks duplicate invoices.
/// @dev Permissionless: anyone may submit a valid buyer signature. No admin.
contract AcceptanceRegistry is EIP712 {
    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "Acceptance(address buyer,address seller,address token,uint256 faceAmount,uint64 dueDate,bytes32 invoiceHash,bytes32 invoiceNumberHash,bytes32 termsHash,address vault,uint256 nonce,uint64 expiry)"
    );

    mapping(bytes32 termsHash => Acceptance) private _acceptances;
    mapping(bytes32 invoiceKey => bool) public invoiceKeyUsed;
    mapping(address buyer => mapping(uint256 nonce => bool)) public nonceUsed;

    event InvoiceAccepted(
        bytes32 indexed termsHash,
        bytes32 indexed invoiceKey,
        address indexed buyer,
        address seller,
        address vault,
        uint256 faceAmount,
        uint64 dueDate
    );

    error AcceptanceExpired();
    error InvalidSignature();
    error NonceUsed();
    error DuplicateInvoice();
    error AlreadyAccepted();
    error ZeroAddress();

    constructor() EIP712("Hundi AcceptanceRegistry", "1") {}

    /// @notice Record a buyer's acceptance. Reverts on expiry, bad signature, nonce reuse or duplicate invoice.
    /// @param a The acceptance as signed by `a.buyer`.
    /// @param sig ECDSA signature, or ERC-1271 signature if `a.buyer` is a contract wallet.
    function accept(Acceptance calldata a, bytes calldata sig) external {
        if (a.buyer == address(0) || a.seller == address(0) || a.vault == address(0)) revert ZeroAddress();
        if (block.timestamp > a.expiry) revert AcceptanceExpired();
        if (_acceptances[a.termsHash].buyer != address(0)) revert AlreadyAccepted();
        if (nonceUsed[a.buyer][a.nonce]) revert NonceUsed();
        bytes32 key = HundiLib.invoiceKey(a.seller, a.buyer, a.invoiceNumberHash);
        if (invoiceKeyUsed[key]) revert DuplicateInvoice();
        if (!SignatureChecker.isValidSignatureNow(a.buyer, digest(a), sig)) revert InvalidSignature();

        nonceUsed[a.buyer][a.nonce] = true;
        invoiceKeyUsed[key] = true;
        _acceptances[a.termsHash] = a;

        emit InvoiceAccepted(a.termsHash, key, a.buyer, a.seller, a.vault, a.faceAmount, a.dueDate);
    }

    /// @notice EIP-712 digest the buyer signs.
    function digest(Acceptance calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ACCEPTANCE_TYPEHASH,
                    a.buyer,
                    a.seller,
                    a.token,
                    a.faceAmount,
                    a.dueDate,
                    a.invoiceHash,
                    a.invoiceNumberHash,
                    a.termsHash,
                    a.vault,
                    a.nonce,
                    a.expiry
                )
            )
        );
    }

    /// @notice Whether an acceptance is recorded for these terms.
    function isAccepted(bytes32 termsHash) external view returns (bool) {
        return _acceptances[termsHash].buyer != address(0);
    }

    /// @notice The recorded acceptance (all-zero if none).
    function acceptanceOf(bytes32 termsHash) external view returns (Acceptance memory) {
        return _acceptances[termsHash];
    }

    /// @notice EIP-712 domain separator, exposed for off-chain signers.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
