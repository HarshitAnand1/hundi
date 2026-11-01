// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HundiBase} from "./utils/HundiBase.sol";
import {ReceivableFactory} from "../src/ReceivableFactory.sol";
import {ReceivableVault} from "../src/ReceivableVault.sol";
import {Terms, Acceptance, HundiLib} from "../src/Types.sol";

contract ReceivableFactoryTest is HundiBase {
    function _accept(Terms memory t, string memory n, uint256 nonce) internal returns (Acceptance memory a) {
        a = _acceptance(t, n, nonce);
        registry.accept(a, _sign(buyerKey, a));
    }

    function test_create_at_predicted_address() public {
        Terms memory t = _terms("INV-1");
        _accept(t, "INV-1", 1);
        address predicted = factory.predictVault(t);
        assertEq(predicted.code.length, 0);

        vm.prank(makeAddr("anyone"));
        address vault = factory.createVault(t);

        assertEq(vault, predicted);
        assertTrue(factory.isVault(vault));
        assertEq(HundiLib.hashTerms(ReceivableVault(vault).terms()), HundiLib.hashTerms(t));
        assertEq(ReceivableVault(vault).factory(), address(factory));
        assertEq(uint256(ReceivableVault(vault).state()), uint256(ReceivableVault.State.Open));
    }

    function test_revert_without_acceptance() public {
        vm.expectRevert(ReceivableFactory.NotAccepted.selector);
        factory.createVault(_terms("INV-1"));
    }

    /// @dev Buyer signed an acceptance pointing at a different vault (payee swap): no vault is created.
    function test_revert_acceptance_vault_mismatch() public {
        Terms memory t = _terms("INV-1");
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        a.vault = makeAddr("attacker");
        registry.accept(a, _sign(buyerKey, a));
        vm.expectRevert(ReceivableFactory.AcceptanceMismatch.selector);
        factory.createVault(t);
    }

    function test_revert_acceptance_amount_mismatch() public {
        Terms memory t = _terms("INV-1");
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        a.faceAmount = FACE + 1;
        registry.accept(a, _sign(buyerKey, a));
        vm.expectRevert(ReceivableFactory.AcceptanceMismatch.selector);
        factory.createVault(t);
    }

    function test_revert_twice() public {
        Terms memory t = _terms("INV-1");
        _accept(t, "INV-1", 1);
        factory.createVault(t);
        vm.expectRevert();
        factory.createVault(t);
    }

    function test_revert_wrong_token() public {
        Terms memory t = _terms("INV-1");
        t.token = makeAddr("USDT");
        vm.expectRevert(ReceivableFactory.TokenNotAllowed.selector);
        factory.createVault(t);
    }

    function test_revert_invalid_terms() public {
        Terms memory t = _terms("INV-1");
        t.advanceBps = 10_001;
        vm.expectRevert(ReceivableFactory.InvalidTerms.selector);
        factory.createVault(t);

        t = _terms("INV-1");
        t.seller = buyer;
        vm.expectRevert(ReceivableFactory.InvalidTerms.selector);
        factory.createVault(t);

        t = _terms("INV-1");
        t.graceSeconds = t.defaultSeconds + 1;
        vm.expectRevert(ReceivableFactory.InvalidTerms.selector);
        factory.createVault(t);
    }

    function test_implementation_cannot_be_initialized() public {
        ReceivableVault impl = ReceivableVault(factory.implementation());
        vm.expectRevert(ReceivableVault.AlreadyInitialized.selector);
        impl.initialize(_terms("INV-1"), 0);
    }

    function test_clone_cannot_be_reinitialized() public {
        Terms memory t = _terms("INV-1");
        _accept(t, "INV-1", 1);
        ReceivableVault v = ReceivableVault(factory.createVault(t));
        t.seller = makeAddr("attacker");
        vm.expectRevert(ReceivableVault.AlreadyInitialized.selector);
        v.initialize(t, 0);
    }

    /// @dev Invariant 6: the vault address is a pure function of the terms. Any changed term moves it.
    function testFuzz_address_commits_to_terms(uint256 face, uint64 due, uint16 adv, address treasury_) public view {
        Terms memory t = _terms("INV-1");
        address base = factory.predictVault(t);
        assertEq(factory.predictVault(t), base, "deterministic");

        Terms memory t2 = _terms("INV-1");
        t2.faceAmount = face;
        t2.dueDate = due;
        t2.advanceBps = adv;
        t2.protocolTreasury = treasury_;
        bool same = face == t.faceAmount && due == t.dueDate && adv == t.advanceBps && treasury_ == t.protocolTreasury;
        assertEq(factory.predictVault(t2) == base, same);
    }
}
