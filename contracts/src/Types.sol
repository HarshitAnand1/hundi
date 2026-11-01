// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Immutable loan terms for one receivable. Hashed into the vault address (HANDOFF 6.1).
/// @dev FROZEN 2026-11-01. Any change here changes every vault address and the TS types in packages/sdk.
struct Terms {
    address seller;
    address buyer;
    address token; // USDC.e only
    uint256 faceAmount;
    uint64 dueDate;
    bytes32 invoiceHash; // keccak256 of the canonical invoice JSON
    uint16 advanceBps; // advance = faceAmount * advanceBps / 10_000
    uint16 feeAnnualBps; // discount fee on the advance, simple interest to dueDate
    uint16 lateAnnualBps; // late interest on the advance after dueDate + graceSeconds
    uint16 bondBps; // bond = advance * bondBps / 10_000, held from the seller's advance
    uint16 protocolFeeBps; // protocol fee = faceAmount * protocolFeeBps / 10_000
    uint64 graceSeconds;
    uint64 defaultSeconds; // declareDefault() allowed after dueDate + defaultSeconds
    address pool;
    address protocolTreasury;
}

/// @notice Buyer-signed EIP-712 acceptance of an invoice and its vault (HANDOFF 6.2).
/// @dev FROZEN 2026-11-01. `invoiceNumberHash` added vs HANDOFF: it is needed to compute invoiceKey
///      (see docs/DECISIONS.md). `expiry` is both the submission deadline and the funding deadline.
struct Acceptance {
    address buyer;
    address seller;
    address token;
    uint256 faceAmount;
    uint64 dueDate;
    bytes32 invoiceHash;
    bytes32 invoiceNumberHash;
    bytes32 termsHash;
    address vault;
    uint256 nonce;
    uint64 expiry;
}

library HundiLib {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;

    function hashTerms(Terms memory t) internal pure returns (bytes32) {
        return keccak256(abi.encode(t));
    }

    function invoiceKey(address seller, address buyer, bytes32 invoiceNumberHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(seller, buyer, invoiceNumberHash));
    }

    function advanceOf(Terms memory t) internal pure returns (uint256) {
        return t.faceAmount * t.advanceBps / BPS;
    }

    function bondOf(Terms memory t) internal pure returns (uint256) {
        return advanceOf(t) * t.bondBps / BPS;
    }

    function protocolFeeOf(Terms memory t) internal pure returns (uint256) {
        return t.faceAmount * t.protocolFeeBps / BPS;
    }

    /// @notice Simple interest: principal * bps * seconds / (10_000 * 365 days), rounded down.
    function interest(uint256 principal, uint256 annualBps, uint256 secondsElapsed) internal pure returns (uint256) {
        return principal * annualBps * secondsElapsed / (BPS * YEAR);
    }
}
