// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {Auction} from "../interfaces/IMidnightAuctionRatifier.sol";

/// @dev keccak256(bytes.concat(AUCTION_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant AUCTION_TYPEHASH = keccak256(
    bytes.concat(
        "Auction(Market market,address maker,uint256 startTime,uint256 endTime,uint256 startTick,uint256 endTick,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,uint128 maxUnits,uint128 maxAssets,uint256 continuousFeeCap)",
        "CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)",
        "Market(uint256 chainId,address midnight,address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)"
    )
);

library AuctionHashLib {
    /// @dev Computes the EIP-712 hash struct of an Auction.
    function hashAuction(Auction memory auction) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AUCTION_TYPEHASH,
                HashLib.hashMarket(auction.market),
                auction.maker,
                auction.startTime,
                auction.endTime,
                auction.startTick,
                auction.endTick,
                auction.group,
                auction.callback,
                keccak256(auction.callbackData),
                auction.receiverIfMakerIsSeller,
                auction.maxUnits,
                auction.maxAssets,
                auction.continuousFeeCap
            )
        );
    }
}
