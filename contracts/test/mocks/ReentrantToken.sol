// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ISettle {
    function settle() external;
}

/// @notice Hostile token that tries to re-enter vault.settle() on every transfer.
contract ReentrantToken is ERC20 {
    address public target;
    bool public reentered;
    bool public reentrySucceeded;

    constructor() ERC20("Hostile", "HOST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTarget(address t) external {
        target = t;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (target != address(0) && from == target && !reentered) {
            reentered = true;
            try ISettle(target).settle() {
                reentrySucceeded = true;
            } catch {}
        }
    }
}
