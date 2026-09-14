// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MidnightAdapterTest.sol";

contract EagerLossCallback {
    struct Action {
        address target;
        bytes data;
        bytes4 expectedRevert;
    }

    address internal immutable midnight;
    Action[] internal actions;

    constructor(address midnight_, address token, address vault) {
        midnight = midnight_;
        IERC20(token).approve(midnight_, type(uint256).max);
        IERC20(token).approve(vault, type(uint256).max);
        IMidnight(midnight_).setIsAuthorized(msg.sender, true, address(this));
    }

    function push(address target, bytes memory data, bytes4 expectedRevert) external {
        actions.push(Action(target, data, expectedRevert));
    }

    function onBuy(bytes32, Market memory, uint256, uint256, uint256, address, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == midnight);
        for (uint256 i; i < actions.length; i++) {
            Action storage action = actions[i];
            (bool success, bytes memory result) = action.target.call(action.data);
            if (action.expectedRevert == bytes4(0)) {
                if (!success) {
                    assembly ("memory-safe") {
                        revert(add(result, 32), mload(result))
                    }
                }
            } else {
                require(!success, "expected callback action to revert");
                require(result.length >= 4 && bytes4(result) == action.expectedRevert, "wrong callback revert");
            }
        }
        return CALLBACK_SUCCESS;
    }
}

contract MidnightAdapterEagerLossTest is MidnightAdapterTest {
    using MathLib for uint256;
    using stdStorage for StdStorage;

    function freshPosition(uint256 tick) internal returns (Offer memory offer) {
        setUpRealVault();
        storedOffer.maker = address(adapter);
        storedOffer.ratifier = address(adapter);
        offer = makeBuyOffer(7 days, 8e18, tick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits / 2, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits - offer.maxUnits / 2, taker);
        directTake(offer);
        deal(address(loanToken), taker, 100e18);
    }

    function directTake(Offer memory offer) internal {
        bytes memory data = sign([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, offer.buy ? taker : address(0), address(0), "");
    }

    function newCallback() internal returns (EagerLossCallback callback) {
        callback = new EagerLossCallback(address(midnight), address(loanToken), address(realVault));
        deal(address(loanToken), address(callback), 100e18);
    }

    function callbackSale(Offer memory offer, EagerLossCallback callback) internal {
        midnight.take(
            offer, sign([offer], signerAllocator), offer.maxUnits, address(callback), address(0), address(callback), ""
        );
    }

    function accruedCallbackSale(Offer memory offer, EagerLossCallback callback) external {
        realVault.accrueInterest();
        callbackSale(offer, callback);
    }

    function realizeDefault(Market memory market, uint256 price) external {
        OracleMock(storedCollaterals[0].oracle).setPrice(price);
        OracleMock(storedCollaterals[1].oracle).setPrice(price);
        midnight.liquidate(market, 0, 0, 0, taker, false, address(this), address(0), "");
    }

    function backing() internal view returns (uint256) {
        return loanToken.balanceOf(address(realVault)) + adapter.realAssets();
    }

    function testEagerLossDeploymentSize() public view {
        assertLe(address(adapter).code.length, 24576, "adapter runtime size");
        assertLe(address(factory).code.length, 24576, "factory runtime size");
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectInitialBuy() public {
        freshPosition(MAX_TICK);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.realAssets(), 8e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectParSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        assertEq(realVault.firstTotalAssets(), 0);
        directTake(makeSellOffer(initial.market, 4e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectSaleAfterDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        assertApproxEqAbs(expected, 6e18, 1);
        directTake(makeSellOffer(initial.market, 2e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectBuyAfterDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        offer.group = bytes32("second purchase");
        midnight.supplyCollateral(initial.market, 0, 2e18, taker);
        directTake(offer);
        assertEq(realVault._totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossUncoveredSaleReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory offer = makeSellOffer(initial.market, 4e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.BufferTooLow.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossUncoveredSaleAfterDefaultReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        Offer memory offer = makeSellOffer(initial.market, 2e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.BufferTooLow.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossBufferedDiscountedSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        deal(address(loanToken), address(realVault), 6e18);
        directTake(makeSellOffer(initial.market, 4e18, MAX_TICK / 2));
        assertEq(realVault._totalAssets(), 10e18);
        assertGe(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCallbackFirstValuationAfterDefaultBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        EagerLossCallback callback = newCallback();
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault), abi.encodeCall(IVaultV2.accrueInterest, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 2e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
        assertEq(realVault.balanceOf(recipient), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCallbackValuationWithoutLossBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault), abi.encodeCall(IVaultV2.accrueInterest, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(realVault.balanceOf(recipient), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossPreaccruedCallbackDepositWorks() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(realVault), abi.encodeCall(realVault.deposit, (1e18, recipient)), bytes4(0));
        this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 11e18);
        assertEq(backing(), 11e18);
        assertEq(realVault.balanceOf(recipient), 1e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringParSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 8e18, 1);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), backing());
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringDiscountedSaleReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        Offer memory offer = makeSellOffer(initial.market, 4e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.BufferTooLow.selector);
        callbackSale(offer, callback);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFullSaleThenCompleteDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(this), abi.encodeCall(this.realizeDefault, (initial.market, 0)), bytes4(0));
        callbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        assertEq(backing(), 10e18);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(adapter.marketIdsLength(), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultAndPositionUpdateDuringSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callback.push(
            address(midnight), abi.encodeCall(IMidnight.updatePosition, (initial.market, address(adapter))), bytes4(0)
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 8e18, 1);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), backing());
    }

    /// forge-config: default.isolate = true
    function testEagerLossSameMarketMutationsBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(callback), true)));
        Offer memory innerBuy = makeBuyOffer(7 days, 1e18, MAX_TICK);
        innerBuy.group = bytes32("nested purchase");
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    innerBuy,
                    sign([innerBuy], signerAllocator),
                    innerBuy.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory innerSell = makeSellOffer(initial.market, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    innerSell,
                    sign([innerSell], signerAllocator),
                    innerSell.maxUnits,
                    address(callback),
                    address(0),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapter.withdrawToVault, (initial.market, 0)),
            IMidnightAdapter.SellInProgress.selector
        );
        (Offer memory forced, bytes32 root_) = makeForceDeallocateOffer(initial.market, 1e15);
        bytes memory data = abi.encode(forced, abi.encode(root_, 0, proof([forced])));
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.forceDeallocate, (address(adapter), data, 1e15, address(callback))),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory externalBuy = makeExternalOffer(initial.market, true, 1e18, MAX_TICK);
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapter.take, (externalBuy, "", externalBuy.maxUnits)),
            IMidnightAdapter.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketSnapshotBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeBuyOffer(6 days, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    sign([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 2e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketBuyRequiresSnapshot(bool accrued) public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeBuyOffer(6 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(inner.market, 0, 2e18, address(callback));
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    sign([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            accrued ? bytes4(0) : IMidnightAdapter.SellInProgress.selector
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        }
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18);
        assertEq(adapter.netCredit(_marketId(inner.market)), accrued ? 1e18 : 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketFullSaleBlocked(bool accrued) public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory second = makeBuyOffer(6 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(second.market, 0, 2e18, taker);
        directTake(second);
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeSellOffer(second.market, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (inner, sign([inner], signerAllocator), inner.maxUnits, address(callback), address(0), address(0), "")
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        }
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.marketIdsLength(), 1);
        assertEq(adapter.netCredit(_marketId(second.market)), 1e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketSaleCannotReuseBuffer() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory second = makeBuyOffer(6 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(second.market, 0, 2e18, taker);
        directTake(second);
        deal(address(loanToken), address(realVault), 1.3e18);
        EagerLossCallback callback = newCallback();
        uint256 tick = TickLib.priceToTick(0.75e18, DEFAULT_TICK_SPACING);
        Offer memory inner = makeSellOffer(second.market, 1e18, tick);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (inner, sign([inner], signerAllocator), inner.maxUnits, address(callback), address(0), address(0), "")
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory outer = makeSellOffer(initial.market, 1e18, tick);
        callbackSale(outer, callback);
        assertEq(adapter.netCredit(_marketId(initial.market)), 7e18);
        assertEq(adapter.netCredit(_marketId(second.market)), 1e18);
        assertGe(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringSaleBlocksOnlyUnassistedReads() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault), abi.encodeCall(IVaultV2.accrueInterest, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.SellInProgress.selector
        );
        this.saleThenDeposit(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 9e18, 1);
        assertEq(realVault._totalAssets(), backing());
    }

    function saleThenDeposit(Offer memory offer, EagerLossCallback callback) external {
        callbackSale(offer, callback);
        assertFalse(midnight.liquidationLocked(_marketId(offer.market), address(adapter)));
        assertEq(realVault.firstTotalAssets(), 0);
        assertEq(realVault.totalAssets(), backing());
        deal(address(loanToken), address(this), 1e18);
        realVault.deposit(1e18, recipient);
    }

    /// forge-config: default.isolate = true
    function testEagerLossPartialSaleThenCompleteDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(this), abi.encodeCall(this.realizeDefault, (initial.market, 0)), bytes4(0));
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(realVault), abi.encodeCall(IVaultV2.accrueInterest, ()), IMidnightAdapter.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), 6e18);
        assertEq(backing(), 6e18);
        assertEq(adapter.marketIdsLength(), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSaleThenDefault(bool zeroSnapshot) public {
        Offer memory initial = freshPosition(MAX_TICK);
        if (zeroSnapshot) {
            stdstore.enable_packed_slots().target(address(realVault)).sig("_totalAssets()").checked_write(uint256(0));
        }
        this.saleThenDefault(makeSellOffer(initial.market, 4e18, MAX_TICK), zeroSnapshot);
    }

    function saleThenDefault(Offer memory offer, bool zeroSnapshot) external {
        directTake(offer);
        assertEq(realVault.firstTotalAssets(), 0);
        assertEq(adapter.realAssets(), 4e18);
        this.realizeDefault(offer.market, 0);
        assertEq(adapter.realAssets(), 0, "temporary valuation cleared in the same transaction");
        realVault.accrueInterest();
        assertEq(realVault.firstTotalAssets(), zeroSnapshot ? 0 : 6e18);
        assertEq(realVault.totalAssets(), zeroSnapshot ? 0 : 6e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSaleDoesNotAccrue(bool takerSale, bool skipCheck) public {
        Offer memory initial = freshPosition(MAX_TICK);
        if (skipCheck) {
            vm.prank(curator);
            adapter.submit(abi.encodeCall(IMidnightAdapter.setSkipBufferCheck, (true)));
            adapter.setSkipBufferCheck(true);
        }
        Offer memory offer = takerSale
            ? makeExternalOffer(initial.market, true, 4e18, MAX_TICK)
            : makeSellOffer(initial.market, 4e18, MAX_TICK);
        this.saleWithoutAccrual(offer, takerSale);
        assertEq(backing(), 10e18);
    }

    function saleWithoutAccrual(Offer memory offer, bool takerSale) external {
        assertEq(realVault.firstTotalAssets(), 0);
        uint256 storedAssets = realVault._totalAssets();
        uint256 lastUpdate = realVault.lastUpdate();
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", offer.maxUnits);
        } else {
            directTake(offer);
        }
        assertEq(realVault.firstTotalAssets(), 0, "sale does not establish a snapshot");
        assertEq(realVault._totalAssets(), storedAssets, "sale does not change stored assets");
        assertEq(realVault.lastUpdate(), lastUpdate, "sale does not advance accrual");
    }

    /// forge-config: default.isolate = true
    function testEagerLossSequentialSalesInSameTransaction() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.sequentialSales(initial.market);
    }

    function sequentialSales(Market memory market) external {
        directTake(makeSellOffer(market, 2e18, MAX_TICK));
        directTake(makeSellOffer(market, 2e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    uint256 internal expectedSaleBaseline;

    function recordSaleBaseline(Market memory market, uint256 soldNet, uint256 oldNet, uint256 remainingInterest)
        external
    {
        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(market, _marketId(market), address(adapter));
        uint256 reconstructed = credit - pendingFee + soldNet;
        uint256 value = reconstructed - remainingInterest.mulDivUp(reconstructed, oldNet);
        uint256 cap = uint256(realVault._totalAssets())
            + uint256(realVault._totalAssets())
                .mulDivDown((block.timestamp - realVault.lastUpdate()) * realVault.maxRate(), 1e18);
        expectedSaleBaseline = MathLib.min(loanToken.balanceOf(address(realVault)) + value, cap);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzDefaultDuringSale(uint256 elapsed, uint256 fee, uint256 sold, bool updatePosition)
        public
    {
        midnight.setDefaultContinuousFee(address(loanToken), bound(fee, 0, MAX_CONTINUOUS_FEE));
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        skip(bound(elapsed, 0, 7 days));
        (uint128 credit, uint128 pendingFee,) =
            midnight.updatePositionView(initial.market, _marketId(initial.market), address(adapter));
        sold = bound(sold, 1, credit);
        uint256 soldNet = sold - uint256(pendingFee).mulDivUp(sold, credit);
        uint256 oldNet = credit - pendingFee;
        uint256 remainingInterest = oldNet - adapter.realAssets();
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        if (updatePosition) {
            callback.push(
                address(midnight),
                abi.encodeCall(IMidnight.updatePosition, (initial.market, address(adapter))),
                bytes4(0)
            );
        }
        callback.push(
            address(this),
            abi.encodeCall(this.recordSaleBaseline, (initial.market, soldNet, oldNet, remainingInterest)),
            bytes4(0)
        );
        uint256 storedAssets = realVault._totalAssets();
        callbackSale(makeSellOffer(initial.market, sold, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), storedAssets, "sale does not accrue");
        assertGe(realVault.totalAssets(), expectedSaleBaseline);
        assertGe(backing(), expectedSaleBaseline);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzSaleBaseline(uint256 elapsed, uint256 fee, uint256 sold, bool loss) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        skip(bound(elapsed, 0, 7 days));
        if (loss) this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        (uint128 credit,,) = midnight.updatePositionView(initial.market, _marketId(initial.market), address(adapter));
        sold = bound(sold, 1, credit);
        uint256 expected = realVault.totalAssets();
        uint256 storedAssets = realVault._totalAssets();
        directTake(makeSellOffer(initial.market, sold, MAX_TICK));
        assertEq(realVault._totalAssets(), storedAssets, "sale does not accrue");
        assertGe(realVault.totalAssets(), expected, "pre-sale baseline preserved");
        assertGe(backing(), expected, "covered sale");
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzBuyAfterDefault(uint256 elapsed, uint256 fee, uint256 assets) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        elapsed = bound(elapsed, 0, 7 days - 1);
        skip(elapsed);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        Offer memory offer = makeBuyOffer(7 days - elapsed, bound(assets, 1e12, 1e18), initial.tick);
        offer.group = bytes32("purchase after default");
        midnight.supplyCollateral(initial.market, 0, offer.maxUnits * 2 + 1e18, taker);
        directTake(offer);
        assertEq(realVault._totalAssets(), expected, "newly bought credit excluded");
        assertGe(backing() + 1, expected, "rounding only");
    }
}
