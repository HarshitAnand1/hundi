// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HundiBase} from "./utils/HundiBase.sol";
import {AcceptanceRegistry} from "../src/AcceptanceRegistry.sol";
import {Terms, Acceptance, HundiLib} from "../src/Types.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

contract AcceptanceRegistryTest is HundiBase {
    function test_accept_records_and_emits() public {
        Terms memory t = _terms("INV-1");
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        bytes32 key = HundiLib.invoiceKey(seller, buyer, a.invoiceNumberHash);

        vm.expectEmit(address(registry));
        emit AcceptanceRegistry.InvoiceAccepted(a.termsHash, key, buyer, seller, a.vault, FACE, t.dueDate);
        registry.accept(a, _sign(buyerKey, a));

        assertTrue(registry.isAccepted(a.termsHash));
        assertEq(registry.acceptanceOf(a.termsHash).vault, a.vault);
        assertTrue(registry.invoiceKeyUsed(key));
        assertTrue(registry.nonceUsed(buyer, 1));
    }

    /// @dev Independent EIP-712 computation; guards against a silent typehash/encoding bug.
    function test_digest_matches_independent_eip712() public view {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Hundi AcceptanceRegistry"),
                keccak256("1"),
                block.chainid,
                address(registry)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Acceptance(address buyer,address seller,address token,uint256 faceAmount,uint64 dueDate,bytes32 invoiceHash,bytes32 invoiceNumberHash,bytes32 termsHash,address vault,uint256 nonce,uint64 expiry)"
                ),
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
        );
        assertEq(registry.domainSeparator(), domain);
        assertEq(registry.digest(a), keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
    }

    function test_revert_expired() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes memory sig = _sign(buyerKey, a);
        vm.warp(a.expiry + 1);
        vm.expectRevert(AcceptanceRegistry.AcceptanceExpired.selector);
        registry.accept(a, sig);
    }

    function test_revert_signed_by_someone_else() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        (, uint256 mallory) = makeAddrAndKey("mallory");
        bytes memory sig = _sign(mallory, a);
        vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
        registry.accept(a, sig);
    }

    function test_revert_field_tampered_after_signing() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes memory sig = _sign(buyerKey, a);
        a.vault = makeAddr("attackerVault"); // payee swap after signature
        vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
        registry.accept(a, sig);
    }

    function test_revert_nonce_reuse() public {
        Acceptance memory a1 = _acceptance(_terms("INV-1"), "INV-1", 1);
        registry.accept(a1, _sign(buyerKey, a1));
        Acceptance memory a2 = _acceptance(_terms("INV-2"), "INV-2", 1);
        bytes memory sig2 = _sign(buyerKey, a2);
        vm.expectRevert(AcceptanceRegistry.NonceUsed.selector);
        registry.accept(a2, sig2);
    }

    /// @dev Same invoice number re-issued with different terms (e.g. new due date) is a duplicate.
    function test_revert_duplicate_invoice_different_terms() public {
        Terms memory t1 = _terms("INV-1");
        Acceptance memory a1 = _acceptance(t1, "INV-1", 1);
        registry.accept(a1, _sign(buyerKey, a1));

        Terms memory t2 = _terms("INV-1");
        t2.dueDate += 10 days;
        Acceptance memory a2 = _acceptance(t2, "INV-1", 2);
        bytes memory sig2 = _sign(buyerKey, a2);
        vm.expectRevert(AcceptanceRegistry.DuplicateInvoice.selector);
        registry.accept(a2, sig2);
    }

    function test_revert_already_accepted() public {
        Terms memory t = _terms("INV-1");
        Acceptance memory a1 = _acceptance(t, "INV-1", 1);
        registry.accept(a1, _sign(buyerKey, a1));
        Acceptance memory a2 = _acceptance(t, "INV-1-b", 2);
        bytes memory sig2 = _sign(buyerKey, a2);
        vm.expectRevert(AcceptanceRegistry.AlreadyAccepted.selector);
        registry.accept(a2, sig2);
    }

    function test_revert_replay_on_other_chain() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes memory sig = _sign(buyerKey, a);
        vm.chainId(999_999);
        vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
        registry.accept(a, sig);
    }

    function test_revert_replay_on_other_registry() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes memory sig = _sign(buyerKey, a);
        AcceptanceRegistry other = new AcceptanceRegistry();
        vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
        other.accept(a, sig);
    }

    function test_revert_zero_address() public {
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        a.vault = address(0);
        vm.expectRevert(AcceptanceRegistry.ZeroAddress.selector);
        registry.accept(a, "");
    }

    function test_erc1271_contract_wallet_buyer() public {
        (address owner, uint256 ownerKey) = makeAddrAndKey("walletOwner");
        MockERC1271Wallet wallet = new MockERC1271Wallet(owner);
        Terms memory t = _terms("INV-1");
        t.buyer = address(wallet);
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        registry.accept(a, _sign(ownerKey, a));
        assertTrue(registry.isAccepted(a.termsHash));
    }

    function test_revert_erc1271_wallet_wrong_key() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet(makeAddr("walletOwner"));
        Terms memory t = _terms("INV-1");
        t.buyer = address(wallet);
        Acceptance memory a = _acceptance(t, "INV-1", 1);
        bytes memory sig = _sign(buyerKey, a);
        vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
        registry.accept(a, sig);
    }

    /// @dev Invariant 5: only the buyer's key produces an accepted record.
    function testFuzz_only_buyer_key_accepts(uint256 key) public {
        key = bound(key, 1, SECP256K1_ORDER - 1);
        Acceptance memory a = _acceptance(_terms("INV-1"), "INV-1", 1);
        bytes memory sig = _sign(key, a);
        if (vm.addr(key) == buyer) {
            registry.accept(a, sig);
        } else {
            vm.expectRevert(AcceptanceRegistry.InvalidSignature.selector);
            registry.accept(a, sig);
        }
    }
}
