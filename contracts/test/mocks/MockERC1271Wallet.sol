// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Contract wallet that accepts signatures from a single owner key (ERC-1271).
contract MockERC1271Wallet is IERC1271 {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered,,) = ECDSA.tryRecover(hash, signature);
        return recovered == owner ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}
