// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Market, Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IBuyCallback, ISellCallback} from "lib/midnight/src/interfaces/ICallbacks.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

struct MaturityData {
    uint128 netCredit;
    uint120 growth;
    uint8 durationCount;
    uint48 prevMaturity;
    uint48 nextMaturity;
}

struct MarketData {
    uint128 netCredit;
    uint120 growth;
}

interface IMidnightAdapter is IAdapter, IBuyCallback, ISellCallback, IRatifier {
    /* EVENTS */

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Accept(bytes4 indexed selector, bytes data);
    event Abdicate(bytes4 indexed selector);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetIsSubRatifier(address indexed subRatifier, bool newIsSubRatifier);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event SetSkipBufferCheck(bool newSkipBufferCheck);
    event Skim(address indexed token, uint256 assets);
    event WithdrawToVault(bytes32 indexed marketId, uint256 withdrawnAssets, uint256 netCreditDecrease);
    event UpdateDurationCaps(uint256 indexed maturity, uint256 newDurationCount, uint256 netCredit);
    event ForceDeallocate(bytes32 indexed marketId, uint256 sellerAssets, uint256 netCreditDecrease);
    event Buy(bytes32 indexed marketId, uint256 paidAssets, uint256 boughtNetCredit, uint256 netCreditLoss);
    event Sell(bytes32 indexed marketId, uint256 sellerAssets, uint256 netCreditDecrease);
    event AccrueInterest(uint128 currentGrowth, uint256 totalAssets);
    event RemoveMaturity(uint256 indexed maturity);
    event InsertMaturity(uint256 indexed maturity);

    /* ERRORS */

    error Abdicated();
    error AutomaticallyTimelocked();
    error BufferTooLow();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error BuyAtLoss();
    error IncorrectCallbackAddress();
    error IncorrectOffer();
    error IncorrectMaker();
    error IncorrectReceiver();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotMidnight();
    error NoDebtCreation();
    error NotSelf();
    error SelfAllocationOnly();
    error SubRatifierUnauthorized();
    error TimelockNotDecreasing();
    error TimelockNotExpired();
    error TimelockNotIncreasing();

    /* FUNCTIONS */

    function asset() external view returns (address);
    function totalAssets() external view returns (uint128);
    function lastUpdate() external view returns (uint48);
    function currentGrowth() external view returns (uint128);
    function availableMaturities() external view returns (uint8);
    function MAX_PENDING_MATURITIES() external view returns (uint8);
    function midnight() external view returns (address);
    function adapterId() external view returns (bytes32);
    function packedDurations() external view returns (bytes32);
    function markets(bytes32 marketId) external view returns (MarketData memory);
    function maturities(uint256 date) external view returns (MaturityData memory);
    function skimRecipient() external view returns (address);
    function skipBufferCheck() external view returns (bool);
    function timelock(bytes4 selector) external view returns (uint256);
    function abdicated(bytes4 selector) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);
    function submit(bytes calldata data) external;
    function revoke(bytes calldata data) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicate(bytes4 selector) external;
    function setSkipBufferCheck(bool newSkipBufferCheck) external;
    function isSubRatifier(address subRatifier) external view returns (bool);
    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external;
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function updateDurationCaps(uint256 maturity) external;
    function withdrawToVault(Market memory market, uint256 withdrawnAssets) external;
    function take(Offer memory offer, bytes memory ratifierData, uint256 units) external;
    function ids(Market memory market) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
    function accrueInterestView() external view returns (uint128, uint256);
    function accrueInterest() external returns (uint128, uint256);
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
