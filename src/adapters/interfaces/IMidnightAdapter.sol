// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Market, Offer} from "../../../lib/midnight/src/interfaces/IMidnight.sol";
import {IBuyCallback, ISellCallback} from "../../../lib/midnight/src/interfaces/ICallbacks.sol";
import {IRatifier} from "../../../lib/midnight/src/interfaces/IRatifier.sol";

struct MarketData {
    uint128 netCredit;
    /// @dev WAD-scaled simple interest rate per second earned on the net credit, so net of Midnight fees.
    uint64 netRate;
    uint48 maturity;
    uint8 index;
    /// @dev Allows selling with arbitrary loss on the market, down to minForceSellPrice, also after maturity.
    /// @dev When activated, netRate isn't reduced on losses due to selling.
    /// @dev When activated, buying is prevented.
    bool forceSellable;
    /// @dev Minimum price of a maker or taker sale while forceSellable, per unit of sold net credit (WAD = face value).
    uint256 minForceSellPrice;
}

/// @dev This interface is used for factorizing IMidnightAdapterStaticTyping and IMidnightAdapter.
/// @dev Consider using the IMidnightAdapter interface instead of this one.
interface IMidnightAdapterBase is IAdapter, IBuyCallback, ISellCallback, IRatifier {
    /* EVENTS */

    event Constructor(address indexed parentVault, address indexed midnight, uint256[] durations);
    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Accept(bytes4 indexed selector, bytes data);
    event Abdicate(bytes4 indexed selector);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetIsSubRatifier(address indexed sender, address indexed subRatifier, bool newIsSubRatifier);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event SetMinNetBuyRate(uint256 newMinNetBuyRate);
    event IncreaseMaxTtm(uint256 newMaxTtm);
    event DecreaseMaxTtm(address indexed sender, uint256 newMaxTtm);
    event SetNoSalesWithShortfall(bool newNoSalesWithShortfall);
    event SetMaxNetSellRate(uint256 newMaxNetSellRate);
    event SetMinForceSellPrice(bytes32 indexed marketId, uint256 newMinForceSellPrice);
    event SetForceSellable(bytes32 indexed marketId);
    event UnsetForceSellable(bytes32 indexed marketId);
    event SetConsumed(address indexed sender, bytes32 indexed group, uint256 amount);
    event Skim(address indexed token, uint256 assets);
    event WithdrawToVault(bytes32 indexed marketId, uint256 withdrawnAssets, uint256 newNetCredit);
    event ForceDeallocate(bytes32 indexed marketId, uint256 assets, uint256 newNetCredit);
    event Buy(
        bytes32 indexed marketId, uint256 paidAssets, uint256 boughtNetCredit, uint256 newNetCredit, uint256 newNetRate
    );
    event Sell(
        bytes32 indexed marketId, uint256 sellerAssets, uint256 soldNetCredit, uint256 newNetCredit, uint256 newNetRate
    );
    event DeferShortfall(
        bytes32 indexed marketId, uint256 shortfall, uint256 newDeferredShortfall, uint256 newReleaseEnd
    );

    /* ERRORS */

    error Abdicated();
    error AutomaticallyTimelocked();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error DurationAbsoluteCapExceeded();
    error DurationRelativeCapExceeded();
    error DurationZeroAbsoluteCap();
    error TooManyDurations();
    error DurationsNotIncreasing();
    error DurationTooHigh();
    error BuyAtLoss();
    error UnauthorizedBuy();
    error BuyPostMaturity();
    error BuyTtmTooHigh();
    error IncorrectCallbackAddress();
    error IncorrectMaker();
    error IncorrectReceiver();
    error InvalidLength();
    error LoanAssetMismatch();
    error MaxTtmTooHigh();
    error MaxTtmTooLow();
    error NotAuthorized();
    error NotMidnight();
    error NotSelf();
    error NonEmptyCallbackData();
    error OtherSellInProgress();
    error NetBuyRateTooLow();
    error SalesWithShortfallDisabled();
    error SelfAllocationOnly();
    error SellInProgress();
    error ForceSellPriceTooLow();
    error NetSellRateTooHigh();
    error SubRatifierFailed();
    error TakerHasNoShares();
    error TimelockNotDecreasing();
    error TimelockNotExpired();
    error TimelockNotIncreasing();
    error TooManyMarkets();

    /* FUNCTIONS */

    function asset() external view returns (address);
    function marketIds(uint256) external view returns (bytes32);
    function marketIdsLength() external view returns (uint256);
    function MAX_MARKETS() external view returns (uint256);
    function MAX_DURATIONS() external view returns (uint256);
    function midnight() external view returns (address);
    function adapterId() external view returns (bytes32);
    function packedDurations() external view returns (bytes32);
    function maxTtm() external view returns (uint32);
    function skimRecipient() external view returns (address);
    function minNetBuyRate() external view returns (uint64);
    function noSalesWithShortfall() external view returns (bool);
    function inProgressBuyMarketId() external view returns (bytes32);
    function inProgressBuyBoughtNetCredit() external view returns (uint256);
    function maxNetSellRate() external view returns (uint64);
    function deferredShortfall() external view returns (uint128);
    function releaseStart() external view returns (uint64);
    function releaseEnd() external view returns (uint64);
    function remainingShortfall() external view returns (uint256);
    function timelock(bytes4 selector) external view returns (uint256);
    function abdicated(bytes4 selector) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);
    function multicall(bytes[] calldata data) external;
    function submit(bytes calldata data) external;
    function revoke(bytes calldata data) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicate(bytes4 selector) external;
    function setMinNetBuyRate(uint256 newMinNetBuyRate) external;
    function increaseMaxTtm(uint256 newMaxTtm) external;
    function decreaseMaxTtm(uint256 newMaxTtm) external;
    function setNoSalesWithShortfall(bool newNoSalesWithShortfall) external;
    function setMaxNetSellRate(uint256 newMaxNetSellRate) external;
    function setMinForceSellPrice(bytes32 marketId, uint256 newMinForceSellPrice) external;
    function setForceSellable(bytes32 marketId) external;
    function unsetForceSellable(bytes32 marketId) external;
    function isSubRatifier(address subRatifier) external view returns (bool);
    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external;
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function durationAllocations(uint256 length) external view returns (uint256[] memory);
    function withdrawToVault(Market memory market, uint256 withdrawnAssets) external;
    function take(Offer memory offer, bytes memory ratifierData, uint256 units, bytes memory takerCallbackData) external;
    function setConsumed(bytes32 group, uint128 amount) external;
    function ids(Market memory market) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
}

/// @dev This interface is inherited by MidnightAdapter so that function signatures are checked by the compiler.
/// @dev Consider using the IMidnightAdapter interface instead of this one.
interface IMidnightAdapterStaticTyping is IMidnightAdapterBase {
    function marketData(bytes32 marketId)
        external
        view
        returns (
            uint128 netCredit,
            uint64 netRate,
            uint48 maturity,
            uint8 index,
            bool forceSellable,
            uint256 minForceSellPrice
        );
}

/// @dev Use this interface for MidnightAdapter to have access to all the functions with the appropriate function signatures.
interface IMidnightAdapter is IMidnightAdapterBase {
    function marketData(bytes32 marketId) external view returns (MarketData memory);
}
