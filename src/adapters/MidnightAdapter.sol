// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MaturityData, MarketData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market, aggregated by maturity.
/// @dev Losses are immediately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy, and the allocator or sentinel role to
/// make sell offers, to withdraw to the vault and to update duration caps.
/// @dev Force deallocators get shares of the adapter's position instead of triggering a market sale. Their claims must
/// stay redeemable even if the vault removes the adapter, so withdrawShares never interacts with the parent vault.
contract MidnightAdapter is IMidnightAdapter {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for int256;
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

    /* MANAGEMENT */

    address public skimRecipient;
    mapping(bytes32 root => bool) public isRootCanceled;

    /* ACCOUNTING */

    uint128 public totalAssets;
    uint128 public currentGrowth;
    uint48 public lastUpdate;
    /// @dev Maximum steps of an accrual.
    /// @dev After accrual, a maturity uses an availability slot iff it has some units and is > now.
    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_PENDING_MATURITIES = 50;
    uint8 public availableMaturities = MAX_PENDING_MATURITIES;
    mapping(uint256 timestamp => MaturityData) public _maturities;
    mapping(bytes32 marketId => MarketData) public _markets;
    mapping(bytes32 marketId => mapping(address user => uint256)) public shares;
    /// @dev Vault net credit decreases realized without interacting with the vault, folded into the change reported
    /// by the next vault interaction on the same market.
    mapping(bytes32 marketId => uint128) public unreportedVaultDecrease;

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

    /* SKIM FUNCTIONS */

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

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

        MarketData storage marketData = _markets[marketId];
        accrueInterest();

        uint256 oldVaultNetCredit = marketData.vaultNetCredit;
        uint256 oldAdapterNetCredit = currentNetCredit(marketId);
        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not call back.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        uint256 withdrawNetCreditDecrease = oldAdapterNetCredit - currentNetCredit(marketId);

        realizeLoss(marketData, marketId, market.maturity, -int256(withdrawNetCreditDecrease));
        removeNetCredit(marketId, market.maturity, withdrawNetCreditDecrease);

        uint256 reportedDecrease = oldVaultNetCredit - marketData.vaultNetCredit + unreportedVaultDecrease[marketId];
        unreportedVaultDecrease[marketId] = 0;
        _maturities[market.maturity].reportedVaultNetCredit -= reportedDecrease.toUint128();
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -reportedDecrease.toInt256()), withdrawnAssets);
        emit WithdrawToVault(marketId, withdrawnAssets, reportedDecrease);
    }

    /// @dev Does not interact with the parent vault, so that claims stay redeemable even if the adapter has been
    /// removed from the vault.
    /// @dev To withdraw early, users can sell on midnight and in a callback immediately repay & withdraw here.
    function withdrawShares(Market memory market, uint256 redeemedShares) external {
        bytes32 marketId = IdLib.toId(market);
        MarketData storage marketData = _markets[marketId];

        accrueInterest();
        IMidnight(midnight).updatePosition(market, address(this));
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;
        realizeLoss(marketData, marketId, market.maturity, 0);
        unreportedVaultDecrease[marketId] += (oldVaultNetCredit - marketData.vaultNetCredit).toUint128();

        uint256 withdrawnAssets = redeemedShares.mulDivDown(marketData.userNetCredit + 1, marketData.userShares + 1);

        uint256 oldAdapterNetCredit = currentNetCredit(marketId);
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), msg.sender);
        uint256 withdrawNetCreditDecrease = oldAdapterNetCredit - currentNetCredit(marketId);
        marketData.userNetCredit -= withdrawNetCreditDecrease.toUint128();
        marketData.userShares -= redeemedShares.toUint128();
        shares[marketId][msg.sender] -= redeemedShares;
        emit WithdrawShares(marketId, msg.sender, redeemedShares, withdrawnAssets);
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
        maturityData.durationCount = uint8(newDurationCount);
        emit UpdateDurationCaps(maturity, newDurationCount, maturityData.reportedVaultNetCredit);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityData.reportedVaultNetCredit > 0) {
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            bytes memory data = abi.encode(zeroedDurationsIds, -int256(uint256(maturityData.reportedVaultNetCredit)));
            IVaultV2(parentVault).deallocate(address(this), data, 0);
        }
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint48, uint128, uint128, uint256) {
        if (block.timestamp == lastUpdate) return (_maturities[0].nextMaturity, currentGrowth, totalAssets, 0);

        uint256 gainedAssets = 0;
        uint128 newGrowth = currentGrowth;
        uint256 accrueFrom = lastUpdate;
        uint48 _firstMaturity = _maturities[0].nextMaturity;
        uint256 removedMaturities = 0;

        while (_firstMaturity != 0 && _firstMaturity <= block.timestamp) {
            gainedAssets += uint256(newGrowth) * (_firstMaturity - accrueFrom);
            newGrowth -= _maturities[_firstMaturity].growth;
            accrueFrom = _firstMaturity;
            _firstMaturity = _maturities[_firstMaturity].nextMaturity;
            removedMaturities++;
        }

        gainedAssets += uint256(newGrowth) * (block.timestamp - accrueFrom);

        return (_firstMaturity, newGrowth, (totalAssets + gainedAssets).toUint128(), removedMaturities);
    }

    function accrueInterest() public returns (uint48, uint128, uint256) {
        if (block.timestamp == lastUpdate) return (_maturities[0].nextMaturity, currentGrowth, totalAssets);

        uint48 newFirstMaturity;
        uint256 removedMaturities;
        (newFirstMaturity, currentGrowth, totalAssets, removedMaturities) = accrueInterestView();
        availableMaturities += uint8(removedMaturities);
        _maturities[0].nextMaturity = newFirstMaturity;
        _maturities[newFirstMaturity].prevMaturity = 0;
        lastUpdate = block.timestamp.toUint48();
        emit AccrueInterest(currentGrowth, totalAssets);

        return (newFirstMaturity, currentGrowth, totalAssets);
    }

    /// @dev Returns an estimate of the real assets assigned to the adapter.
    /// @dev Excludes assets reserved for users.
    function realAssets() external view returns (uint256) {
        (,, uint256 newTotalAssets,) = accrueInterestView();
        return newTotalAssets;
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can be called by this adapter from a buy callback.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(caller == address(this), SelfAllocationOnly());
        // Return exactly the data passed to the function.
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Can be called by this adapter from a sell callback, a withdraw, or a duration caps update.
    /// @dev Can be called by anyone through forceDeallocate.
    /// @dev A force deallocator forfeits all his share of the pending continuous fee.
    function deallocate(bytes memory data, uint256 deallocatedAmount, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            Market memory market = abi.decode(data, (Market));
            bytes32 marketId = IdLib.toId(market);
            MarketData storage marketData = _markets[marketId];
            uint256 oldVaultNetCredit = marketData.vaultNetCredit;

            accrueInterest();
            IMidnight(midnight).updatePosition(market, address(this));
            realizeLoss(marketData, marketId, market.maturity, 0);

            uint256 mintedShares =
                deallocatedAmount.mulDivDown(uint256(marketData.userShares) + 1, uint256(marketData.userNetCredit) + 1);
            shares[marketId][caller] += mintedShares;
            marketData.userShares += mintedShares.toUint128();
            marketData.userNetCredit += deallocatedAmount.toUint128();
            removeNetCredit(marketId, market.maturity, deallocatedAmount);

            uint256 reportedDecrease = oldVaultNetCredit - marketData.vaultNetCredit + unreportedVaultDecrease[marketId];
            unreportedVaultDecrease[marketId] = 0;
            _maturities[market.maturity].reportedVaultNetCredit -= reportedDecrease.toUint128();
            emit ForceDeallocate(marketId, deallocatedAmount, reportedDecrease);
            return (ids(market), -reportedDecrease.toInt256());
        } else {
            require(caller == address(this), SelfAllocationOnly());
            // Return exactly the data passed to the function.
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MIDNIGHT CALLBACKS */

    function cancelRoot(bytes32 root) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        isRootCanceled[root] = true;
        emit CancelRoot(msg.sender, root);
    }

    function isRatified(Offer memory offer, bytes memory data, address) external view returns (bytes32) {
        // Collaterals will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectOwner());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());
        require(offer.buy || offer.reduceOnly, NoDebtCreation());

        (Signature memory sig, bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(data, (Signature, bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        require(!isRootCanceled[root], RootCanceled());
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(proof.length), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        // forge-lint: disable-next-item(ecrecover) offer sizes & cancellation protects against reuse.
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), IncorrectSigner());
        require(IVaultV2(parentVault).isAllocator(signer), IncorrectSigner());

        return CALLBACK_SUCCESS;
    }

    function onBuy(
        bytes32 marketId,
        Market memory market,
        uint256 paidAssets,
        uint256 boughtCredit,
        uint256 buyPendingFeeIncrease,
        address buyer,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());

        accrueInterest();

        MaturityData storage maturityData = _maturities[market.maturity];
        MarketData storage marketData = _markets[marketId];
        if (maturityData.reportedVaultNetCredit == 0) {
            maturityData.durationCount = uint8(durationCount(market.maturity));
        }
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;
        realizeLoss(marketData, marketId, market.maturity, int256(boughtNetCredit));

        if (timeToMaturity > 0) {
            uint256 interest = boughtNetCredit - paidAssets;
            uint128 growthIncrease = (interest / timeToMaturity).toUint128();
            totalAssets += (paidAssets + interest % timeToMaturity).toUint128();
            marketData.growth += growthIncrease;
            maturityData.growth += growthIncrease;
            currentGrowth += growthIncrease;
        } else {
            totalAssets += boughtNetCredit.toUint128();
        }

        maturityData.vaultNetCredit += boughtNetCredit.toUint128();
        marketData.vaultNetCredit += boughtNetCredit.toUint128();

        int256 netCreditChange = int256(uint256(marketData.vaultNetCredit)) - int256(oldVaultNetCredit)
            - int256(uint256(unreportedVaultDecrease[marketId]));
        unreportedVaultDecrease[marketId] = 0;
        maturityData.reportedVaultNetCredit =
            (int256(uint256(maturityData.reportedVaultNetCredit)) + netCreditChange).toUint256().toUint128();
        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(market), netCreditChange), paidAssets);

        // Insert the maturity in the list if needed
        if (maturityData.vaultNetCredit == boughtNetCredit && boughtNetCredit > 0 && market.maturity > block.timestamp)
        {
            availableMaturities--;
            uint48 prevMaturity = 0;
            uint48 nextMaturity = _maturities[0].nextMaturity;
            while (nextMaturity != 0 && nextMaturity < market.maturity) {
                prevMaturity = nextMaturity;
                nextMaturity = _maturities[prevMaturity].nextMaturity;
            }
            maturityData.nextMaturity = _maturities[prevMaturity].nextMaturity;
            maturityData.prevMaturity = prevMaturity;
            _maturities[prevMaturity].nextMaturity = market.maturity.toUint48();
            _maturities[maturityData.nextMaturity].prevMaturity = market.maturity.toUint48();
            emit InsertMaturity(market.maturity);
        }

        emit Buy(marketId, paidAssets, boughtNetCredit, netCreditChange);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256 units,
        uint256 sellPendingFeeDecrease,
        address seller,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());

        accrueInterest();

        MarketData storage marketData = _markets[marketId];
        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;
        uint256 sellNetCreditDecrease = units - sellPendingFeeDecrease;

        realizeLoss(marketData, marketId, market.maturity, -int256(sellNetCreditDecrease));
        removeNetCredit(marketId, market.maturity, sellNetCreditDecrease);

        uint256 reportedDecrease = oldVaultNetCredit - marketData.vaultNetCredit + unreportedVaultDecrease[marketId];
        unreportedVaultDecrease[marketId] = 0;
        _maturities[market.maturity].reportedVaultNetCredit -= reportedDecrease.toUint128();
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -reportedDecrease.toInt256()), sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());

        emit Sell(marketId, sellerAssets, reportedDecrease);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    function currentNetCredit(bytes32 marketId) internal view returns (uint256) {
        return
            IMidnight(midnight).credit(marketId, address(this))
                - IMidnight(midnight).pendingFee(marketId, address(this));
    }

    /// @dev Realizes any loss between the expected and actual net credit.
    /// @dev Splits the loss between users and vault, and updates vault accounting.
    /// @dev The vault-side decrease is not reported here; callers report it or accumulate it in
    /// unreportedVaultDecrease.
    function realizeLoss(
        MarketData storage marketData,
        bytes32 marketId,
        uint256 maturity,
        int256 expectedAdapterNetCreditDelta
    ) internal {
        uint256 currentAdapterNetCredit = currentNetCredit(marketId);
        uint256 oldAdapterNetCredit = marketData.vaultNetCredit + marketData.userNetCredit;
        uint256 expectedAdapterNetCredit = (int256(oldAdapterNetCredit) + expectedAdapterNetCreditDelta).toUint256();
        if (expectedAdapterNetCredit > currentAdapterNetCredit) {
            uint256 loss = expectedAdapterNetCredit - currentAdapterNetCredit;
            uint256 userLoss =
                oldAdapterNetCredit == 0 ? 0 : uint256(marketData.userNetCredit).mulDivUp(loss, oldAdapterNetCredit);
            uint256 vaultLoss = loss - userLoss;
            marketData.userNetCredit -= uint128(userLoss);
            if (vaultLoss > 0) removeNetCredit(marketId, maturity, vaultLoss);
        }
    }

    /// @dev Removes netCredit proportionally from current accounted assets and future growth.
    function removeNetCredit(bytes32 marketId, uint256 maturity, uint256 removedNetCredit) internal {
        if (removedNetCredit == 0) return;

        MaturityData storage maturityData = _maturities[maturity];
        MarketData storage marketData = _markets[marketId];

        if (maturity > block.timestamp) {
            uint256 timeToMaturity = maturity - block.timestamp;
            uint128 growthDecrease = marketData.growth.mulDivUp(removedNetCredit, marketData.vaultNetCredit).toUint128();
            marketData.growth -= growthDecrease;
            maturityData.growth -= growthDecrease;
            currentGrowth -= growthDecrease;
            totalAssets = (totalAssets + (growthDecrease * timeToMaturity) - removedNetCredit).toUint128();
        } else {
            totalAssets -= removedNetCredit.toUint128();
        }
        maturityData.vaultNetCredit -= removedNetCredit.toUint128();
        marketData.vaultNetCredit -= removedNetCredit.toUint128();

        if (maturityData.vaultNetCredit == 0 && maturity > block.timestamp) {
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

    /* UNUSED CALLBACKS */
}
