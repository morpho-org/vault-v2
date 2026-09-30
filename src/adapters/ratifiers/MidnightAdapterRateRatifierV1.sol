// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IMidnightAdapterRateRatifierV1,
    Ratification,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IMidnightAdapterRateRatifierV1.sol";
import {SET_IS_ROOT_RATIFIED_SUCCESS} from "lib/midnight/src/ratifiers/interfaces/IRatifiersV1Common.sol";
import {Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {TickLib} from "lib/midnight/src/libraries/TickLib.sol";
import {UtilsLib} from "lib/midnight/src/libraries/UtilsLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";

import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IMidnightAdapter} from "../interfaces/IMidnightAdapter.sol";

/// @dev See comments in lib/midnight/src/ratifiers/RateRatifierV1.sol. The difference is that roots are ratified by the parent vault's allocators and sentinels instead of the maker's authorized addresses.
/// @dev Allocators of the adapter's parent vault can ratify or unratify roots; sentinels can only unratify.
/// @dev Approved roots remain ratified after an allocator is removed, until explicitly unratified.
contract MidnightAdapterRateRatifierV1 is IMidnightAdapterRateRatifierV1 {
    using UtilsLib for uint256;

    mapping(address maker => mapping(bytes32 root => Ratification)) public ratification;

    function isRootRatified(address maker, bytes32 root) external view returns (bool) {
        return ratification[maker][root].isRootRatified;
    }

    function rootNonce(address maker, bytes32 root) external view returns (uint128) {
        return ratification[maker][root].rootNonce;
    }

    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external returns (bytes32) {
        address parentVault = IMidnightAdapter(maker).parentVault();
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsRootRatified && IVaultV2(parentVault).isSentinel(msg.sender)),
            Unauthorized()
        );
        ratification[maker][root].isRootRatified = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, maker, root, newIsRootRatified);
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// @dev Permissioned to not let people extract the signature of a batch and start taking before or take even though the batch reverted. Both the caller and the signer are subject to the same authorization as setIsRootRatified.
    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        uint256 height,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        address parentVault = IMidnightAdapter(maker).parentVault();
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsRootRatified && IVaultV2(parentVault).isSentinel(msg.sender)),
            Unauthorized()
        );
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(HashLib.rateRatifierV1OfferTreeTypeHash(height), maker, root, newIsRootRatified, nonce, deadline)
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address _signer = ecrecover(digest, v, r, s);
        require(_signer != address(0), InvalidSignature());
        require(
            IVaultV2(parentVault).isAllocator(_signer)
                || (!newIsRootRatified && IVaultV2(parentVault).isSentinel(_signer)),
            Unauthorized()
        );
        Ratification memory _ratification = ratification[maker][root];
        if (nonce == _ratification.rootNonce) {
            ratification[maker][root] = Ratification({isRootRatified: newIsRootRatified, rootNonce: nonce + 1});
        } else {
            require(nonce < _ratification.rootNonce, InvalidNonce());
            require(_ratification.isRootRatified == newIsRootRatified, RatifiedStatusChanged());
        }
        emit SetIsRootRatifiedWithSig(
            msg.sender, _signer, maker, root, height, newIsRootRatified, nonce, _ratification.rootNonce
        );
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address taker) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof, uint256 rate, address allowedTaker) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[], uint256, address));
        require(allowedTaker == address(0) || taker == allowedTaker, UnauthorizedTaker());
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        if (offer.buy) require(offerPrice <= WAD.mulDivDown(WAD, WAD + rate * timeToMaturity), WorsePrice());
        else require(offerPrice >= WAD.mulDivUp(WAD, WAD + rate * timeToMaturity), WorsePrice());
        require(
            HashLib.isLeaf(root, HashLib.hashRateRatifierV1Offer(offer, rate, allowedTaker), leafIndex, proof),
            InvalidProof()
        );
        require(ratification[offer.maker][root].isRootRatified, NotRatified());
        return CALLBACK_SUCCESS;
    }
}
