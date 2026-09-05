// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "lib/midnight/src/periphery/libraries/TakeAmountsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MaturityData, MarketData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market, aggregated by maturity.
/// @dev Any interest excluded from growth due to rounding is realized immediately.
/// @dev Losses are immediately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy, and the allocator or sentinel role to
/// make sell offers, to withdraw to the vault and to update duration caps.
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be
/// deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapter {
    using MathLib for uint256;
    using MathLib for uint120;
    using DurationsLib for bytes32;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Durations that can be used to cap the time to maturity.
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* MANAGEMENT */

    address public skimRecipient;
    bool public skipBufferCheck;
    mapping(address subRatifier => bool) public isSubRatifier;

    /* ACCOUNTING */

    /// @dev Maximum steps of an accrual.
    /// @dev A maturity uses an availability slot iff it has some credit and is > now.
    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_PENDING_MATURITIES = 50;

    uint128 public totalAssets;
    uint128 public currentGrowth;
    uint48 public lastUpdate;
    uint8 public availableMaturities = MAX_PENDING_MATURITIES;
    /// @dev Ascending linked list of the future maturities where the adapter has credit.
    /// @dev _maturities[0] is the list head, 0 terminates the list.
    mapping(uint256 timestamp => MaturityData) internal _maturities;
    mapping(bytes32 marketId => MarketData) internal _markets;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
        lastUpdate = block.timestamp.toUint48();
        SafeERC20Lib.safeApprove(asset, _midnight, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        adapterId = keccak256(abi.encode("this", address(this)));

        packedDurations = DurationsLib.pack(_durations);
        durationsLength = _durations.length;
    }

    /* GETTERS */

    function maturities(uint256 date) public view returns (MaturityData memory) {
        return _maturities[date];
    }

    /// @dev Returns the growth of the market. Can be stale after maturity.
    function markets(bytes32 marketId) public view returns (MarketData memory) {
        return _markets[marketId];
    }

    /// @dev Returns the durations that can be capped.
    /// @dev A market position fills the cap of any duration that was <= its time to maturity at the first buy of its
    /// maturity, or at the last updateDurationCaps call for its maturity.
    function durations() public view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /* RATIFIERS */

    /// @dev Sub-ratifiers can approve any offer of the adapter that passes the checks of isRatified, akin to
    /// allocators signing offer trees.
    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsSubRatifier && IVaultV2(parentVault).isSentinel(msg.sender)),
            NotAuthorized()
        );
        isSubRatifier[subRatifier] = newIsSubRatifier;
        emit SetIsSubRatifier(subRatifier, newIsSubRatifier);
    }

    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        // Collaterals will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());
        require(offer.buy || offer.reduceOnly, NoDebtCreation());

        (address subRatifier, bytes memory subData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierUnauthorized());
        return IRatifier(subRatifier).isRatified(offer, subData, taker);
    }

    /* TIMELOCKS FUNCTIONS */

    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block
    /// timestamp.
    function submit(bytes calldata data) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(executableAt[data] == 0, DataAlreadyPending());

        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        uint256 _timelock =
            selector == IMidnightAdapter.decreaseTimelock.selector ? timelock[bytes4(data[4:8])] : timelock[selector];
        executableAt[data] = block.timestamp + _timelock;
        emit Submit(selector, data, executableAt[data]);
    }

    function timelocked() internal {
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(msg.data);
        require(executableAt[msg.data] != 0, DataNotTimelocked());
        require(block.timestamp >= executableAt[msg.data], TimelockNotExpired());
        require(!abdicated[selector], Abdicated());
        executableAt[msg.data] = 0;
        emit Accept(selector, msg.data);
    }

    function revoke(bytes calldata data) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        require(executableAt[data] != 0, DataNotTimelocked());
        executableAt[data] = 0;
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        emit Revoke(msg.sender, selector, data);
    }

    /* CURATOR FUNCTIONS */

    /// @dev This function requires great caution because it can irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before increasing a timelock can still be executed at the initial
    /// executableAt.
    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapter.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration >= timelock[selector], TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapter.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration <= timelock[selector], TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit DecreaseTimelock(selector, newDuration);
    }

    /// @dev This function requires great caution because it will irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before abdicating can not be executed at the initial executableAt.
    function abdicate(bytes4 selector) external {
        timelocked();
        abdicated[selector] = true;
        emit Abdicate(selector);
    }

    function setSkipBufferCheck(bool newSkipBufferCheck) external {
        timelocked();
        skipBufferCheck = newSkipBufferCheck;
        emit SetSkipBufferCheck(newSkipBufferCheck);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /* SKIM FUNCTIONS */

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /* VAULT ALLOCATORS FUNCTIONS */

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) external {
        bytes32 marketId = IdLib.toId(market);
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );

        accrueInterest();

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not call back.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        // current net credit cannot be > accounted net credit
        uint256 netCreditDecrease = _markets[marketId].netCredit - currentNetCredit(marketId);

        decreaseNetCredit(marketId, market.maturity, netCreditDecrease);

        // forge-lint: disable-next-item(unsafe-typecast) netCreditDecrease <= type(uint128).max.
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -int256(netCreditDecrease)), withdrawnAssets);
        emit WithdrawToVault(marketId, withdrawnAssets, netCreditDecrease);
    }

    function take(Offer memory offer, bytes memory ratifierData, uint256 units) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        IMidnight(midnight)
            .take(
                offer, ratifierData, units, address(this), offer.buy ? address(this) : address(0), address(this), hex""
            );
    }

    /// @dev Remove the maturity allocation from the duration ids that are > its time to maturity.
    function updateDurationCaps(uint256 maturity) external {
        MaturityData storage maturityData = _maturities[maturity];
        uint256 oldDurationCount = maturityData.durationCount;
        uint256 newDurationCount = durationCount(maturity);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityData.netCredit > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) newDurationCount <= MAX_DURATIONS.
            maturityData.durationCount = uint8(newDurationCount);
            emit UpdateDurationCaps(maturity, newDurationCount, maturityData.netCredit);
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            bytes memory data = abi.encode(zeroedDurationsIds, -int256(uint256(maturityData.netCredit)));
            IVaultV2(parentVault).deallocate(address(this), data, 0);
        }
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint128, uint256) {
        if (block.timestamp == lastUpdate) return (currentGrowth, totalAssets);

        uint128 newGrowth = currentGrowth;
        uint256 newTotalAssets = totalAssets;
        uint256 accrueFrom = lastUpdate;
        uint48 maturity = _maturities[0].nextMaturity;

        while (maturity != 0 && maturity <= block.timestamp) {
            newTotalAssets += uint256(newGrowth) * (maturity - accrueFrom);
            newGrowth -= _maturities[maturity].growth;
            accrueFrom = maturity;
            maturity = _maturities[maturity].nextMaturity;
        }
        newTotalAssets += newGrowth * (block.timestamp - accrueFrom);

        return (newGrowth, newTotalAssets);
    }

    function accrueInterest() public returns (uint128, uint256) {
        if (block.timestamp == lastUpdate) return (currentGrowth, totalAssets);

        uint128 newGrowth = currentGrowth;
        uint256 newTotalAssets = totalAssets;
        uint256 accrueFrom = lastUpdate;
        uint48 maturity = _maturities[0].nextMaturity;
        uint256 removedMaturities;

        while (maturity != 0 && maturity <= block.timestamp) {
            newTotalAssets += uint256(newGrowth) * (maturity - accrueFrom);
            newGrowth -= _maturities[maturity].growth;
            accrueFrom = maturity;
            maturity = _maturities[maturity].nextMaturity;
            removedMaturities++;
        }
        if (removedMaturities > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) removedMaturities <= MAX_PENDING_MATURITIES.
            availableMaturities += uint8(removedMaturities);
            _maturities[0].nextMaturity = maturity;
            _maturities[maturity].prevMaturity = 0;
            currentGrowth = newGrowth;
        }
        newTotalAssets += newGrowth * (block.timestamp - accrueFrom);

        totalAssets = newTotalAssets.toUint128();
        lastUpdate = block.timestamp.toUint48();
        emit AccrueInterest(newGrowth, newTotalAssets);

        return (newGrowth, newTotalAssets);
    }

    /// @dev Returns an estimate of the real assets assigned to the adapter.
    function realAssets() external view returns (uint256) {
        (, uint256 newTotalAssets) = accrueInterestView();
        return newTotalAssets;
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can be called by this adapter from a buy callback.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        require(caller == address(this), SelfAllocationOnly());
        // Return exactly the data passed to the function.
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Can be called by this adapter from a sell callback, a withdraw, or a duration caps update.
    /// @dev Can be called by anyone through forceDeallocate to trigger a sell take by the adapter.
    function deallocate(bytes memory data, uint256 sellerAssets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, bytes memory ratifierData) = abi.decode(data, (Offer, bytes));
            require(
                offer.buy && offer.market.loanToken == asset && offer.tick == MAX_TICK && offer.callback == address(0),
                IncorrectOffer()
            );

            accrueInterest();

            // Skip onSell since we are already in a deallocate call.
            bytes32 marketId = IdLib.toId(offer.market);
            uint256 takeUnits = TakeAmountsLib.sellerAssetsToUnits(midnight, marketId, offer, sellerAssets);
            // forge-lint: disable-next-item(reentrancy-no-eth) view reentry is possible through a ratifier.
            IMidnight(midnight).take(offer, ratifierData, takeUnits, address(this), address(this), address(0), hex"");
            // current net credit cannot be > accounted net credit
            uint256 netCreditDecrease = _markets[marketId].netCredit - currentNetCredit(marketId);
            decreaseNetCredit(marketId, offer.market.maturity, netCreditDecrease);

            emit ForceDeallocate(marketId, sellerAssets, netCreditDecrease);
            // forge-lint: disable-next-item(unsafe-typecast) netCreditDecrease <= type(uint128).max.
            return (ids(offer.market), -int256(netCreditDecrease));
        } else {
            require(caller == address(this), SelfAllocationOnly());
            // Return exactly the data passed to the function.
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MIDNIGHT CALLBACKS */

    function onBuy(
        bytes32 marketId,
        Market memory market,
        uint256 paidAssets,
        uint256 boughtCredit,
        uint256 buyPendingFeeIncrease,
        address buyer,
        bytes memory callbackData
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());
        accrueInterest();

        MaturityData storage maturityData = _maturities[market.maturity];
        MarketData storage marketData = _markets[marketId];
        // forge-lint: disable-next-item(unsafe-typecast) durationCount <= MAX_DURATIONS.
        if (maturityData.netCredit == 0) maturityData.durationCount = uint8(durationCount(market.maturity));
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        // current net credit cannot be > accounted net credit + bought net credit
        uint256 netCreditLoss = marketData.netCredit + boughtNetCredit - currentNetCredit(marketId);
        decreaseNetCredit(marketId, market.maturity, netCreditLoss);
        uint256 idleAssets = IERC20(asset).balanceOf(parentVault);
        if (callbackData.length > 0 && paidAssets > idleAssets) {
            (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
            // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
            IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets - idleAssets);
        }

        // forge-lint: disable-next-item(reentrancy-no-eth) reentry is expected.
        IVaultV2(parentVault)
            .allocate(
                address(this),
                abi.encode(ids(market), boughtNetCredit.toInt256() - netCreditLoss.toInt256()),
                paidAssets
            );

        if (timeToMaturity > 0) {
            uint256 interest = boughtNetCredit - paidAssets;
            uint120 growthIncrease = (interest / timeToMaturity).toUint120();
            totalAssets += (paidAssets + interest % timeToMaturity).toUint128();
            marketData.growth += growthIncrease;
            maturityData.growth += growthIncrease;
            currentGrowth += growthIncrease;

            if (maturityData.netCredit == 0 && boughtNetCredit > 0) {
                availableMaturities--;
                uint48 prevMaturity = 0;
                uint48 nextMaturity = _maturities[0].nextMaturity;
                while (nextMaturity != 0 && nextMaturity < market.maturity) {
                    prevMaturity = nextMaturity;
                    nextMaturity = _maturities[nextMaturity].nextMaturity;
                }
                maturityData.prevMaturity = prevMaturity;
                maturityData.nextMaturity = nextMaturity;
                _maturities[prevMaturity].nextMaturity = market.maturity.toUint48();
                _maturities[nextMaturity].prevMaturity = market.maturity.toUint48();
                emit InsertMaturity(market.maturity);
            }
        } else {
            totalAssets += boughtNetCredit.toUint128();
        }

        maturityData.netCredit += boughtNetCredit.toUint128();
        marketData.netCredit += boughtNetCredit.toUint128();

        emit Buy(marketId, paidAssets, boughtNetCredit, netCreditLoss);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256,
        uint256,
        address seller,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());

        accrueInterest();

        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
        // current net credit cannot be > accounted net credit
        uint256 netCreditDecrease = _markets[marketId].netCredit - currentNetCredit(marketId);
        decreaseNetCredit(marketId, market.maturity, netCreditDecrease);

        // forge-lint: disable-next-item(unsafe-typecast) netCreditDecrease <= type(uint128).max.
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -int256(netCreditDecrease)), sellerAssets);

        if (!skipBufferCheck) {
            uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(parentVault);
            uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
            for (uint256 i = 0; i < adaptersLength; i++) {
                vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
            }
            require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());
        }

        emit Sell(marketId, sellerAssets, netCreditDecrease);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    function currentNetCredit(bytes32 marketId) internal view returns (uint256) {
        return
            IMidnight(midnight).credit(marketId, address(this))
                - IMidnight(midnight).pendingFee(marketId, address(this));
    }

    /// @dev Decreases netCredit proportionally from current accounted assets and future growth.
    function decreaseNetCredit(bytes32 marketId, uint256 maturity, uint256 netCreditDecrease) internal {
        if (netCreditDecrease == 0) return;

        MaturityData storage maturityData = _maturities[maturity];
        MarketData storage marketData = _markets[marketId];

        if (maturity > block.timestamp) {
            uint256 timeToMaturity = maturity - block.timestamp;
            uint120 growthDecrease = marketData.growth.mulDivUp(netCreditDecrease, marketData.netCredit).toUint120();
            marketData.growth -= growthDecrease;
            maturityData.growth -= growthDecrease;
            currentGrowth -= growthDecrease;
            totalAssets = (totalAssets + (growthDecrease * timeToMaturity) - netCreditDecrease).toUint128();
        } else {
            totalAssets -= netCreditDecrease.toUint128();
        }
        maturityData.netCredit -= netCreditDecrease.toUint128();
        marketData.netCredit -= netCreditDecrease.toUint128();

        if (maturityData.netCredit == 0 && maturity > block.timestamp) {
            availableMaturities++;
            _maturities[maturityData.prevMaturity].nextMaturity = maturityData.nextMaturity;
            _maturities[maturityData.nextMaturity].prevMaturity = maturityData.prevMaturity;
            emit RemoveMaturity(maturity);
        }
    }

    /// @dev Returns the number of durations in packedDurations that are at most the time to maturity.
    function durationCount(uint256 maturity) internal view returns (uint256 count) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (count < durationsLength && timeToMaturity >= packedDurations.get(count)) count++;
    }

    /// @dev Liquidation cursors are omitted from collateral ids.
    function ids(Market memory market) public view returns (bytes32[] memory) {
        uint256 durationsCount = _maturities[market.maturity].durationCount;

        bytes32[] memory idsArray = new bytes32[](1 + market.collateralParams.length * 2 + durationsCount);

        uint256 j;
        idsArray[j++] = adapterId;
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            address collateralToken = market.collateralParams[i].token;
            idsArray[j++] = keccak256(abi.encode("collateralToken", collateralToken));
            idsArray[j++] = keccak256(
                abi.encode(
                    "collateral", collateralToken, market.collateralParams[i].oracle, market.collateralParams[i].lltv
                )
            );
        }
        for (uint256 i = 0; i < durationsCount; i++) {
            idsArray[j++] = keccak256(abi.encode("duration", packedDurations.get(i)));
        }

        return idsArray;
    }
}
