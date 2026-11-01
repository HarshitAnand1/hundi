// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AcceptanceRegistry} from "../src/AcceptanceRegistry.sol";
import {Terms, Acceptance, HundiLib} from "../src/Types.sol";

/// @notice Cross-language test vectors. packages/sdk/test/vectors.test.ts asserts the same constants.
contract VectorsTest is Test {
    address constant REGISTRY = 0x7777777777777777777777777777777777777777;

    function _terms() internal pure returns (Terms memory) {
        return Terms({
            seller: 0x1111111111111111111111111111111111111111,
            buyer: 0x2222222222222222222222222222222222222222,
            token: 0x3333333333333333333333333333333333333333,
            faceAmount: 10_000e6,
            dueDate: 1_800_000_000,
            invoiceHash: keccak256("vector-invoice"),
            advanceBps: 9000,
            feeAnnualBps: 800,
            lateAnnualBps: 1800,
            bondBps: 200,
            protocolFeeBps: 10,
            graceSeconds: 259_200,
            defaultSeconds: 2_592_000,
            pool: 0x4444444444444444444444444444444444444444,
            protocolTreasury: 0x5555555555555555555555555555555555555555
        });
    }

    function test_vectors_match_sdk() public {
        Terms memory t = _terms();
        bytes32 th = HundiLib.hashTerms(t);
        bytes32 key = HundiLib.invoiceKey(t.seller, t.buyer, keccak256("INV-VECTOR-1"));

        vm.chainId(133);
        deployCodeTo("AcceptanceRegistry.sol:AcceptanceRegistry", REGISTRY);
        Acceptance memory a = Acceptance({
            buyer: t.buyer,
            seller: t.seller,
            token: t.token,
            faceAmount: t.faceAmount,
            dueDate: t.dueDate,
            invoiceHash: t.invoiceHash,
            invoiceNumberHash: keccak256("INV-VECTOR-1"),
            termsHash: th,
            vault: 0x6666666666666666666666666666666666666666,
            nonce: 1,
            expiry: 1_790_604_800
        });
        bytes32 digest = AcceptanceRegistry(REGISTRY).digest(a);
        assertEq(th, 0x7ccba115c1eb1a4076e584ef91f3f88a76a5c45d320f03f44f5a521218e435ec, "termsHash");
        assertEq(key, 0xe9296aec573dd3985831885224c3aa12d561a822886af9a0c91ba6b4f8f76b69, "invoiceKey");
        assertEq(digest, 0x8f90a5dfabcaf815366f431885044d97b4ee870b86a014c598b3bd930aae3037, "acceptance digest");
    }
}
