// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapterBase, IMidnightAdapterStaticTyping, MarketData} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";
import {SharesLib} from "./libraries/SharesLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market.
/// @dev Growth is rounded down. Interest excluded from growth is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault and to sell (except through forceDeallocate).
/// @dev Buy offers must set callbackData (takes of sell offers must set takerCallbackData) to abi.encode(adapter, data) to select where the liquidity will be deallocated, or to "" to pull the liquidity from the vault's idle funds, or to abi.encode(address(this), market) to withdraw from another midnight market on the adapter.
/// @dev For self-funding, data is abi.encode(fundingMarket).
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
/// @dev A sale has a shortfall when the proceeds are less than the amortized value of the sold net credit.
/// @dev A shortfall decreases growth, so the amortized value of the market decreases only by the received assets.
/// @dev Bad debt that is visible in onSell is applied before the shortfall.
/// @dev This includes bad debt realized during the sale (e.g. in the buyer callback), which then overvalues the market by at most the shortfall, decreasing to zero at maturity.
/// @dev The adapter's allocation cap bounds exposure.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapterStaticTyping {
    using MathLib for uint256;
    using MathLib for uint64;
    using MathLib for uint48;
    using DurationsLib for bytes32;
    using SharesLib for uint256;

    /* CONSTANTS */

    /// @dev Fillable with dust takes.
    uint256 public constant MAX_MARKETS = 250;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Durations that can be used to cap the time to maturity.
    /// @dev A duration of 0 can effectively always be used, through adapterId, since it means capping all midnight markets.
    /// @dev Sorted in ascending order.
    /// @dev The caps of a duration are the vault's caps of the id keccak256(abi.encode("duration", adapter, duration)).
    /// @dev The vault's allocation of this id stays zero: the adapter enforces these caps itself on buys.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TRANSIENT STORAGE */

    bytes32 transient overridenMarketId;
    uint256 transient overridenMarketNetCredit;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* ADAPTER STORAGE */

    address public skimRecipient;
    mapping(address subRatifier => bool) public isSubRatifier;

    bytes32[] public marketIds;
    /// @dev netCredit is vault-owned credit last reported to the vault's caps; claims do not overwrite it.
    /// @dev Ownership shares persist when a market is removed from marketIds.
    mapping(bytes32 marketId => MarketData) public marketData;
    mapping(bytes32 marketId => mapping(address holder => uint256)) public claimShares;

    uint32 public maxTtm;
    /// @dev Minimum growth of a market after a maker or taker buy, or after a loss sale.
    uint64 public minGrowth;
    bool public noShortfall;

    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
        SafeERC20Lib.safeApprove(asset, _midnight, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        adapterId = keccak256(abi.encode("this", address(this)));

        packedDurations = DurationsLib.pack(_durations);
        durationsLength = _durations.length;
    }

    /* TIMELOCK FUNCTIONS */

    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block timestamp.
    function submit(bytes calldata data) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(executableAt[data] == 0, DataAlreadyPending());

        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        uint256 _timelock = selector == IMidnightAdapterBase.decreaseTimelock.selector
            ? timelock[bytes4(data[4:8])]
            : timelock[selector];
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

    /// @dev This function requires great caution because it can irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before increasing a timelock can still be executed at the initial executableAt.
    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapterBase.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration >= timelock[selector], TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapterBase.decreaseTimelock.selector, AutomaticallyTimelocked());
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

    /* CURATOR FUNCTIONS */

    function setMaxTtm(uint256 newMaxTtm) external {
        timelocked();
        maxTtm = newMaxTtm.toUint32();
        emit SetMaxTtm(newMaxTtm);
    }

    function setForceSellable(bytes32 marketId) external {
        timelocked();
        marketData[marketId].forceSellable = true;
        emit SetForceSellable(marketId);
    }

    function unsetForceSellable(bytes32 marketId) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        marketData[marketId].forceSellable = false;
        emit UnsetForceSellable(marketId);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Help prevent operational errors when buying.
    /// @dev Also bounds the growth decrease of loss sales.
    function setMinGrowth(uint256 newMinGrowth) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minGrowth = newMinGrowth.toUint64();
        emit SetMinGrowth(newMinGrowth);
    }

    /// @dev Help prevent operational errors when selling.
    function setNoShortfall(bool newNoShortfall) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        noShortfall = newNoShortfall;
        emit SetNoShortfall(newNoShortfall);
    }

    /* ALLOCATOR FUNCTIONS */

    function take(Offer memory offer, bytes memory ratifierData, uint256 units, bytes memory takerCallbackData)
        external
    {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        IMidnight(midnight)
            .take(
                offer,
                ratifierData,
                units,
                address(this),
                offer.buy ? address(this) : address(0),
                address(this),
                takerCallbackData
            );
    }

    /// @dev Setting type(uint128).max cancels all offers of the adapter in the group.
    function setConsumed(bytes32 group, uint128 amount) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        IMidnight(midnight).setConsumed(group, amount, address(this));
        emit SetConsumed(msg.sender, group, amount);
    }

    /// @dev Sub-ratifiers define how allocator offers are authorized.
    /// @dev The sentinel can only remove sub-ratifiers.
    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsSubRatifier && IVaultV2(parentVault).isSentinel(msg.sender)),
            NotAuthorized()
        );
        isSubRatifier[subRatifier] = newIsSubRatifier;
        emit SetIsSubRatifier(msg.sender, subRatifier, newIsSubRatifier);
    }

    /* OPERATIONS */

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) public {
        bytes32 marketId = IdLib.toId(market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
        uint128 credit = midnightCredit(market);
        burnVaultShares(marketId, withdrawnAssets, credit);

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 oldNetCredit = marketData[marketId].netCredit;
        marketData[marketId].netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(reentrancy-no-eth, unsafe-typecast) deallocate does not call withdrawToVault; both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                withdrawnAssets
            );
        emit WithdrawToVault(marketId, withdrawnAssets, newNetCredit);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /* VAULT INTERFACE */

    /// @dev Called by this adapter from a buy callback to update the vault's allocations.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        require(caller == address(this), SelfAllocationOnly());
        returnExactBytes(data);
    }

    /// @dev Called by this adapter from a sell callback or a withdraw.
    /// @dev forceDeallocate data is abi.encode(market, claimReceiver).
    /// @dev Exchanges caller-funded cash for existing gross credit; no market trade or entry gate is needed.
    function deallocate(bytes memory data, uint256 assets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Market memory market, address receiver) = abi.decode(data, (Market, address));
            require(market.loanToken == asset, LoanAssetMismatch());
            bytes32 marketId = IdLib.toId(market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            IVaultV2(parentVault).accrueInterest();
            MarketData storage _marketData = marketData[marketId];
            uint128 credit = midnightCredit(market);
            uint256 shares = moveVaultSharesToClaim(marketId, receiver, assets, credit);
            uint128 newNetCredit = currentNetCredit(marketId);
            uint256 oldNetCredit = _marketData.netCredit;
            _marketData.netCredit = newNetCredit;
            if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
            // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
            int256 change = int256(uint256(newNetCredit)) - int256(oldNetCredit);
            SafeERC20Lib.safeTransferFrom(asset, caller, address(this), assets);
            emit ForceDeallocate(caller, marketId, receiver, assets, shares, change);
            return (ids(market), change);
        } else {
            require(caller == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /// @dev Pays directly from Midnight, independently of vault roles, gates, or registration.
    /// @dev Liquidity is first come, first served. Failed withdrawals revert the share burn.
    function redeemClaimWithdraw(Market memory market, uint256 shares, address receiver) external returns (uint256) {
        bytes32 marketId = IdLib.toId(market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());

        uint256 assets = burnClaimShares(marketId, msg.sender, shares, midnightCredit(market));

        IMidnight(midnight).withdraw(market, assets, address(this), receiver);
        // Keep marketData.netCredit as the last value reported to the parent vault.
        emit RedeemClaimWithdraw(msg.sender, marketId, receiver, assets, shares);
        return assets;
    }

    /// @dev Sells `units` of the caller's claim to a Midnight buy offer, independently of vault roles, gates, or registration.
    /// @dev No taker callback is set, so onSell doesn't run and marketData.netCredit stays the last value reported to the parent vault.
    /// @dev Burned shares round up against the pre-sale gross credit to protect the vault and other claims.
    function redeemClaimSell(Offer memory offer, bytes memory ratifierData, uint256 units, address receiver)
        external
        returns (uint256 shares, uint256 sellerAssets)
    {
        require(offer.buy, NotBuyOffer());
        bytes32 marketId = IdLib.toId(offer.market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());

        shares = burnClaimSharesForAssets(marketId, msg.sender, units, midnightCredit(offer.market));

        (, sellerAssets) = IMidnight(midnight).take(offer, ratifierData, units, address(this), receiver, address(0), "");
        emit RedeemClaimSell(msg.sender, marketId, receiver, units, sellerAssets, shares);
    }

    /* MIDNIGHT CALLBACKS */

    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Gates, RCF threshold, collaterals and durations will be checked in onBuy.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());

        (address subRatifier, bytes memory subRatifierData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierFailed());
        return IRatifier(subRatifier).isRatified(offer, subRatifierData, taker);
    }

    /// @dev Between recording the purchase and vault.allocate's transfer, realAssets() includes the purchase but the vault has not paid yet.
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
        require(block.timestamp < market.maturity, BuyPostMaturity());
        uint256 ttm = market.maturity - block.timestamp;
        require(ttm <= maxTtm, BuyTtmTooHigh());
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        uint128 rawNetCredit = positionNetCredit(marketId);
        uint256 previousNetCredit = rawNetCredit - boughtNetCredit;
        uint256 previousVaultNetCredit = vaultNetCredit(marketId, previousNetCredit);
        (overridenMarketId, overridenMarketNetCredit) = (marketId, previousVaultNetCredit);
        // forge-lint: disable-next-item(reentrancy-no-eth) accrueInterest only calls view functions of adapters.
        IVaultV2(parentVault).accrueInterest();
        (overridenMarketId, overridenMarketNetCredit) = (0, 0);

        MarketData storage _marketData = marketData[marketId];
        require(!_marketData.forceSellable, UnauthorizedBuy());
        mintVaultShares(marketId, boughtNetCredit, previousNetCredit);

        uint128 newNetCredit = vaultNetCredit(marketId, rawNetCredit).toUint128();
        uint256 addedVaultNetCredit = newNetCredit - previousVaultNetCredit;
        require(addedVaultNetCredit >= paidAssets, BuyAtLoss());
        require(boughtCredit == 0 || addedVaultNetCredit > 0, ZeroClaimOutput());

        if (newNetCredit > 0) {
            uint256 amortizedValue = previousVaultNetCredit.mulDivUp(WAD - _marketData.growth * ttm, WAD) + paidAssets;
            // forge-lint: disable-next-item(unsafe-typecast) growth <= WAD < 2**64.
            _marketData.growth = uint64((newNetCredit - amortizedValue).mulDivDown(WAD, newNetCredit * ttm));
            require(_marketData.growth >= minGrowth, BuyGrowthTooLow());
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit > 0 && oldNetCredit == 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            _marketData.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            _marketData.index = uint8(marketIds.length);
            marketIds.push(marketId);
        } else if (newNetCredit == 0 && oldNetCredit > 0) {
            removeMarket(marketId);
        }
        uint256 idleAssets = IERC20(asset).balanceOf(parentVault);
        if (callbackData.length > 0 && paidAssets > idleAssets) {
            (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
            if (fundingAdapter == address(this)) {
                withdrawToVault(abi.decode(fundingData, (Market)), paidAssets - idleAssets);
            } else {
                // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
                IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets - idleAssets);
            }
        }

        // Only durations up to the bought market's time to maturity can have their allocation increased.
        uint256 affectedDurationCount;
        while (affectedDurationCount < durationsLength && packedDurations.get(affectedDurationCount) <= ttm) {
            affectedDurationCount++;
        }
        uint256[] memory allocations = durationAllocations(affectedDurationCount);
        uint256 totalAssets = IVaultV2(parentVault).firstTotalAssets();
        for (uint256 i; i < affectedDurationCount; i++) {
            bytes32 id = keccak256(abi.encode("duration", address(this), packedDurations.get(i)));
            require(allocations[i] <= IVaultV2(parentVault).absoluteCap(id), DurationAbsoluteCapExceeded());
            uint256 relativeCap = IVaultV2(parentVault).relativeCap(id);
            require(
                relativeCap == WAD || allocations[i] <= totalAssets.mulDivDown(relativeCap, WAD),
                DurationRelativeCapExceeded()
            );
        }

        // forge-lint: disable-next-item(reentrancy-no-eth, unsafe-typecast) reentry is expected; both net credit values fit in uint128.
        IVaultV2(parentVault)
            .allocate(
                address(this), abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)), paidAssets
            );

        emit Buy(marketId, paidAssets, boughtNetCredit, _marketData.netCredit, _marketData.growth);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256 soldCredit,
        uint256 sellPendingFeeDecrease,
        address seller,
        address,
        bytes memory callbackData
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());
        require(callbackData.length == 0, NonEmptyCallbackData());

        require(IMidnight(midnight).debt(marketId, address(this)) == 0, InsufficientVaultCredit());
        uint256 soldNetCredit = soldCredit - sellPendingFeeDecrease;
        uint256 previousVaultNetCredit = vaultNetCredit(marketId, uint256(positionNetCredit(marketId)) + soldNetCredit);
        uint128 credit = midnightCredit(market);
        MarketData storage _marketData = marketData[marketId];
        if (soldCredit > 0) {
            // Midnight already deducted the sale. Round up against pre-sale gross credit to protect claims.
            burnVaultShares(marketId, soldCredit, uint256(credit) + soldCredit);
        }
        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 ttm = market.maturity.zeroFloorSub(block.timestamp);
        if (!_marketData.forceSellable) {
            uint256 shortfall = (previousVaultNetCredit - newNetCredit)
                .mulDivUp(WAD - _marketData.growth * ttm, WAD)
                .zeroFloorSub(sellerAssets);
            if (shortfall > 0) {
                uint256 maxShortfall =
                    noShortfall ? 0 : (newNetCredit * ttm).mulDivDown(_marketData.growth.zeroFloorSub(minGrowth), WAD);
                require(shortfall <= maxShortfall, ShortfallTooHigh());

                _marketData.growth -= shortfall.mulDivUp(WAD, newNetCredit * ttm).toUint64();
            }
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                sellerAssets
            );

        emit Sell(marketId, sellerAssets, soldNetCredit, newNetCredit, _marketData.growth);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Ends the external call, returning data without ABI encoding.
    function returnExactBytes(bytes memory data) internal pure {
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Returns the full position net credit, including claim holders' ownership.
    /// @dev It does not change with time, so any market struct with maturity 0 will work.
    function positionNetCredit(bytes32 marketId) internal view returns (uint128) {
        Market memory dummyMarket;
        (uint128 credit, uint128 pendingFee,) =
            IMidnight(midnight).updatePositionView(dummyMarket, marketId, address(this));
        return credit - pendingFee;
    }

    function currentNetCredit(bytes32 marketId) internal view returns (uint128) {
        return vaultNetCredit(marketId, positionNetCredit(marketId)).toUint128();
    }

    function vaultNetCredit(bytes32 marketId, uint256 credit) internal view returns (uint256) {
        MarketData storage _marketData = marketData[marketId];
        return uint256(_marketData.vaultShares).toAssetsDown(credit, _marketData.totalShares);
    }

    /* SHARES */

    // Only these five functions modify totalShares, vaultShares and claimShares, so that totalShares equals vaultShares plus the sum of claimShares.

    /// @dev Mints vault shares worth `assets` out of `totalAssets`, rounding down.
    function mintVaultShares(bytes32 marketId, uint256 assets, uint256 totalAssets) internal returns (uint256 shares) {
        MarketData storage _marketData = marketData[marketId];
        shares = assets.toSharesDown(totalAssets, _marketData.totalShares);
        _marketData.totalShares = (_marketData.totalShares + shares).toUint128();
        _marketData.vaultShares = (_marketData.vaultShares + shares).toUint128();
    }

    /// @dev Burns vault shares worth `assets` out of `totalAssets`, rounding up.
    function burnVaultShares(bytes32 marketId, uint256 assets, uint256 totalAssets) internal returns (uint256 shares) {
        MarketData storage _marketData = marketData[marketId];
        shares = assets.toSharesUp(totalAssets, _marketData.totalShares);
        _marketData.totalShares -= shares.toUint128();
        _marketData.vaultShares -= shares.toUint128();
    }

    /// @dev Moves vault shares worth `assets` out of `totalAssets` to `receiver`'s claim, rounding down.
    function moveVaultSharesToClaim(bytes32 marketId, address receiver, uint256 assets, uint256 totalAssets)
        internal
        returns (uint256 shares)
    {
        MarketData storage _marketData = marketData[marketId];
        shares = assets.toSharesDown(totalAssets, _marketData.totalShares);
        _marketData.vaultShares -= shares.toUint128();
        claimShares[marketId][receiver] += shares;
    }

    /// @dev Burns `holder`'s claim `shares` and returns their value out of `totalAssets`, rounding down.
    function burnClaimShares(bytes32 marketId, address holder, uint256 shares, uint256 totalAssets)
        internal
        returns (uint256 assets)
    {
        MarketData storage _marketData = marketData[marketId];
        assets = shares.toAssetsDown(totalAssets, _marketData.totalShares);
        claimShares[marketId][holder] -= shares;
        _marketData.totalShares -= shares.toUint128();
    }

    /// @dev Burns `holder`'s claim shares worth `assets` out of `totalAssets`, rounding up.
    function burnClaimSharesForAssets(bytes32 marketId, address holder, uint256 assets, uint256 totalAssets)
        internal
        returns (uint256 shares)
    {
        MarketData storage _marketData = marketData[marketId];
        shares = assets.toSharesUp(totalAssets, _marketData.totalShares);
        claimShares[marketId][holder] -= shares;
        _marketData.totalShares -= shares.toUint128();
    }

    /// @dev Removes the market from marketIds and clears vault metadata, preserving ownership for claims and forceSellable.
    function removeMarket(bytes32 marketId) internal {
        MarketData storage _marketData = marketData[marketId];
        bytes32 lastMarketId = marketIds[marketIds.length - 1];
        marketIds[_marketData.index] = lastMarketId;
        marketData[lastMarketId].index = _marketData.index;
        marketIds.pop();
        _marketData.netCredit = 0;
        _marketData.growth = 0;
        _marketData.maturity = 0;
        _marketData.index = 0;
    }

    /* VIEWS */

    /// @notice Current gross Midnight credit backing both vault shares and claims.
    /// @dev Applies losses and accrued fees; remaining pending fees are not subtracted.
    function midnightCredit(Market memory market) public view returns (uint128 credit) {
        (credit,,) = IMidnight(midnight).updatePositionView(market, IdLib.toId(market), address(this));
    }

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    function ids(Market memory market) public view returns (bytes32[] memory) {
        bytes32[] memory idsArray = new bytes32[](4 + market.collateralParams.length * 2);

        uint256 j;
        idsArray[j++] = adapterId;
        idsArray[j++] = keccak256(abi.encode("enterGate", market.enterGate));
        idsArray[j++] = keccak256(abi.encode("liquidatorGate", market.liquidatorGate));
        idsArray[j++] = keccak256(abi.encode("rcfThreshold", market.rcfThreshold));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            idsArray[j++] = keccak256(abi.encode("collateralToken", market.collateralParams[i].token));
            idsArray[j++] = keccak256(abi.encode("collateralParams", market.collateralParams[i]));
        }

        return idsArray;
    }

    /// @dev Returns the durations that can be capped.
    /// @dev A position counts toward every duration <= its current remaining time to maturity.
    function durations() external view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /// @dev Returns, for the first length durations, the stored net credit of markets with at least that duration left to maturity.
    /// @dev Stored exposure includes unreported losses; claim-redemption rounding can leave small surpluses.
    function durationAllocations(uint256 length) public view returns (uint256[] memory allocations) {
        require(length <= durationsLength, InvalidLength());
        allocations = new uint256[](length);
        if (length == 0) return allocations;
        for (uint256 i; i < marketIds.length; i++) {
            MarketData storage _marketData = marketData[marketIds[i]];
            uint256 ttm = uint256(_marketData.maturity).zeroFloorSub(block.timestamp);
            uint256 bucket;
            while (bucket < length && packedDurations.get(bucket) <= ttm) bucket++;
            if (bucket > 0) allocations[bucket - 1] += _marketData.netCredit;
        }
        for (uint256 j = length - 1; j > 0; j--) {
            allocations[j - 1] += allocations[j];
        }
    }

    function realAssets() external view returns (uint256) {
        uint256 assets;
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData storage _marketData = marketData[marketId];
            uint256 netCredit;
            if (marketId == overridenMarketId) {
                netCredit = overridenMarketNetCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), OtherSellInProgress());
                netCredit = currentNetCredit(marketId);
            }
            assets += netCredit.mulDivDown(
                WAD - _marketData.growth * _marketData.maturity.zeroFloorSub(block.timestamp), WAD
            );
        }
        return assets;
    }
}
