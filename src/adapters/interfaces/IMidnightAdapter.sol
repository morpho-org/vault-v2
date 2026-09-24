// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Market, Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IBuyCallback, ISellCallback} from "lib/midnight/src/interfaces/ICallbacks.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

struct MarketData {
    uint128 netCredit;
    /// @dev Each unit of growth represents 1/WAD of the net credit accrued per second, until maturity.
    uint64 growth;
    uint48 maturity;
    uint8 index;
}

struct MaturityData {
    uint128 netCredit;
    uint8 durationCount;
}

interface IMidnightAdapter is IAdapter, IBuyCallback, ISellCallback, IRatifier {
    /* EVENTS */

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Accept(bytes4 indexed selector, bytes data);
    event Abdicate(bytes4 indexed selector);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event AddSubRatifier(address indexed subRatifier);
    event RemoveSubRatifier(address indexed sender, address indexed subRatifier);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event SetMinBuyRate(uint256 newMinBuyRate);
    event SetMaxSellRate(address indexed sender, bytes32 indexed collateralParamsHash, uint256 newMaxSellRate);
    event SetConsumed(address indexed sender, bytes32 indexed group, uint256 amount);
    event Skim(address indexed token, uint256 assets);
    event WithdrawToVault(bytes32 indexed marketId, uint256 withdrawnAssets, uint256 netCreditDecrease);
    event UpdateDurationCaps(uint256 indexed maturity, uint256 newDurationCount, uint256 netCredit);
    event Buy(bytes32 indexed marketId, uint256 paidAssets, uint256 boughtNetCredit, uint256 netCreditLoss);
    event Sell(bytes32 indexed marketId, uint256 sellerAssets, uint256 netCreditDecrease);
    event UpdateMarket(bytes32 indexed marketId, uint256 netCredit, uint256 growth);

    /* ERRORS */

    error Abdicated();
    error AutomaticallyTimelocked();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error BuyAtLoss();
    error BuyPostMaturity();
    error IncorrectCallbackAddress();
    error IncorrectOffer();
    error IncorrectMaker();
    error IncorrectReceiver();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotMidnight();
    error NotSelf();
    error OtherSellInProgress();
    error BuyRateTooLow();
    error SelfAllocationOnly();
    error SellInProgress();
    error SellRateTooHigh();
    error SubRatifierFailed();
    error TimelockNotDecreasing();
    error TimelockNotExpired();
    error TimelockNotIncreasing();
    error TooManyMarkets();
    error VaultNotAccrued();

    /* FUNCTIONS */

    function asset() external view returns (address);
    function marketIds(uint256) external view returns (bytes32);
    function marketIdsLength() external view returns (uint256);
    function MAX_MARKETS() external view returns (uint8);
    function PAR_SELL_GROUP() external view returns (bytes32);
    function midnight() external view returns (address);
    function adapterId() external view returns (bytes32);
    function packedDurations() external view returns (bytes32);
    function marketData(bytes32 marketId) external view returns (MarketData memory);
    function maturities(uint256 date) external view returns (MaturityData memory);
    function skimRecipient() external view returns (address);
    function minBuyRate() external view returns (uint256);
    function maxSellRate(bytes32 collateralParamsHash) external view returns (uint256);
    function timelock(bytes4 selector) external view returns (uint256);
    function abdicated(bytes4 selector) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);
    function submit(bytes calldata data) external;
    function revoke(bytes calldata data) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicate(bytes4 selector) external;
    function setMinBuyRate(uint256 newMinBuyRate) external;
    function setMaxSellRate(bytes32 collateralParamsHash, uint256 newMaxSellRate) external;
    function isSubRatifier(address subRatifier) external view returns (bool);
    function addSubRatifier(address subRatifier) external;
    function removeSubRatifier(address subRatifier) external;
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function updateDurationCaps(uint256 maturity) external;
    function withdrawToVault(Market memory market, uint256 withdrawnAssets) external;
    function take(Offer memory offer, bytes memory ratifierData, uint256 units) external;
    function setConsumed(bytes32 group, uint128 amount) external;
    function ids(Market memory market) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
    function allocate(bytes memory data, uint256 assets, bytes4, address caller)
        external
        returns (bytes32[] memory, int256);
    function deallocate(bytes memory data, uint256 assets, bytes4, address caller)
        external
        returns (bytes32[] memory, int256);
    function onBuy(
        bytes32 id,
        Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external returns (bytes32);
    function onSell(
        bytes32 id,
        Market memory market,
        uint256 sellerAssets,
        uint256 units,
        uint256 pendingFeeDecrease,
        address seller,
        address receiver,
        bytes memory data
    ) external returns (bytes32);
}
