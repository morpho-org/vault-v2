// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IMidnightAdapter} from "../interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterEcrecoverRatifier} from "./interfaces/IMidnightAdapterEcrecoverRatifier.sol";

/// @dev Sub-ratifier for MidnightAdapter offers: checks that the offer has been signed by an allocator of the maker
/// adapter's parent vault in a Merkle tree of offers. To that end, it expects the ratifier data to contain the
/// signature, the root of the tree, the leaf index of the offer, and the proof of the offer in the tree.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev The leaf index determines each sibling's left/right position.
/// @dev Hashing offers as in EIP-712, which allows clear signing of the tree, credits to Seaport for this mechanism.
/// @dev Same tree format and signing scheme as Midnight's EcrecoverRatifier.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed offers are
/// no longer valid.
contract MidnightAdapterEcrecoverRatifier is IMidnightAdapterEcrecoverRatifier {
    mapping(address adapter => mapping(bytes32 root => bool)) public isRootCanceled;

    /// @dev All offers in a tree are expected to share the same maker adapter. Otherwise all offers in a tree might
    /// not be cancelled by a single call to this function.
    function cancelRoot(address adapter, bytes32 root) external {
        address parentVault = IMidnightAdapter(adapter).parentVault();
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        isRootCanceled[adapter][root] = true;
        emit CancelRoot(msg.sender, adapter, root);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address) external view returns (bytes32) {
        (Signature memory sig, bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(ratifierData, (Signature, bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        require(!isRootCanceled[offer.maker][root], RootCanceled());
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(proof.length), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        // forge-lint: disable-next-item(ecrecover) offer sizes & cancellation protects against reuse.
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), IncorrectSigner());
        require(IVaultV2(IMidnightAdapter(offer.maker).parentVault()).isAllocator(signer), IncorrectSigner());

        return CALLBACK_SUCCESS;
    }
}
