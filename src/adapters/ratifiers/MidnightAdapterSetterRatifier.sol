// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IMidnightAdapter} from "../interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterSetterRatifier} from "./interfaces/IMidnightAdapterSetterRatifier.sol";

/// @dev Sub-ratifier for MidnightAdapter offers: checks that the offer has been ratified onchain by an allocator of
/// the maker adapter's parent vault in a Merkle tree of offers. To that end, it expects the ratifier data to contain
/// the root of the tree, the leaf index of the offer in the tree, and the proof of the offer in the tree.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev The leaf index determines each hash order during merkle proof verification.
/// @dev Same tree format as Midnight's SetterRatifier.
contract MidnightAdapterSetterRatifier is IMidnightAdapterSetterRatifier {
    mapping(address adapter => mapping(bytes32 root => bool)) public isRootRatified;

    /// @dev All offers in a tree are expected to share the same maker adapter. Otherwise all offers in a tree might
    /// not be ratified or unratified by a single call to this function.
    function setIsRootRatified(address adapter, bytes32 root, bool newIsRootRatified) external {
        address parentVault = IMidnightAdapter(adapter).parentVault();
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsRootRatified && IVaultV2(parentVault).isSentinel(msg.sender)),
            NotAuthorized()
        );
        isRootRatified[adapter][root] = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, adapter, root, newIsRootRatified);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        require(isRootRatified[offer.maker][root], NotRatified());

        return CALLBACK_SUCCESS;
    }
}
