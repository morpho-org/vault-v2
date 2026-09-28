// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

import "./MidnightAdapterTest.sol";

/// @dev Maker of a forceDeallocate buy offer that is also its own onBuy callback (and thus the payer). Runs a list
/// of actions inside the callback; each action either must succeed (expectedRevert 0) or must revert with the
/// given selector.
contract ForceDeallocateBuyer {
    struct Action {
        address target;
        bytes data;
        bytes4 expectedRevert;
    }

    address internal immutable midnight;
    Action[] internal actions;
    bool public called;

    constructor(address midnight_) {
        midnight = midnight_;
    }

    function push(address target, bytes memory data, bytes4 expectedRevert) external {
        actions.push(Action(target, data, expectedRevert));
    }

    function exec(address target, bytes memory data) external returns (bytes memory result) {
        bool success;
        (success, result) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function onBuy(bytes32, Market memory, uint256, uint256, uint256, address buyer, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == midnight, "not midnight");
        require(buyer == address(this), "not buyer");
        // Nested takes with this contract as maker must not re-run the actions.
        if (called) return CALLBACK_SUCCESS;
        called = true;
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

/// @dev What a buyer callback can and cannot do while the adapter sells to it through forceDeallocate.
contract MidnightAdapterForceDeallocateCallbackTest is MidnightAdapterTest {
    using MathLib for uint256;

    SetterRatifier internal buyerRatifier;

    function newBuyer() internal returns (ForceDeallocateBuyer buyer) {
        buyer = new ForceDeallocateBuyer(address(midnight));
        buyerRatifier = new SetterRatifier(address(midnight));
        deal(address(loanToken), address(buyer), 100e18);
        buyer.exec(address(loanToken), abi.encodeCall(IERC20.approve, (address(midnight), type(uint256).max)));
        buyer.exec(address(loanToken), abi.encodeCall(IERC20.approve, (address(adapter), type(uint256).max)));
        buyer.exec(address(loanToken), abi.encodeCall(IERC20.approve, (address(realVault), type(uint256).max)));
        buyer.exec(
            address(midnight), abi.encodeCall(IMidnight.setIsAuthorized, (address(buyerRatifier), true, address(buyer)))
        );
    }

    /// @dev Par buy offer made by `buyer`, with `buyer` as callback, ratified through buyerRatifier.
    function callbackOffer(Market memory market, uint256 assets, ForceDeallocateBuyer buyer)
        internal
        returns (Offer memory, bytes memory)
    {
        return callbackOffer(market, assets, buyer, MAX_TICK);
    }

    function callbackOffer(Market memory market, uint256 assets, ForceDeallocateBuyer buyer, uint256 tick)
        internal
        returns (Offer memory offer, bytes memory ratifierData_)
    {
        offer = storedOffer;
        offer.market = market;
        offer.buy = true;
        offer.maker = address(buyer);
        offer.tick = tick;
        offer.maxUnits = uint128(assets);
        offer.expiry = block.timestamp;
        offer.callback = address(buyer);
        offer.callbackData = hex"";
        offer.receiverIfMakerIsSeller = address(0);
        offer.ratifier = address(buyerRatifier);
        offer.group = bytes32(vm.randomUint());
        bytes32 root_ = HashLib.hashOffer(offer);
        buyer.exec(
            address(buyerRatifier), abi.encodeCall(SetterRatifier.setIsRootRatified, (address(buyer), root_, true))
        );
        ratifierData_ = abi.encode(root_, uint256(0), new bytes32[](0));
    }

    function callbackForceDeallocate(Market memory market, uint256 assets, ForceDeallocateBuyer buyer)
        internal
        returns (uint256)
    {
        (Offer memory offer, bytes memory ratifierData_) = callbackOffer(market, assets, buyer);
        loanToken.approve(address(adapter), assets);
        return realVault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData_), assets, address(this));
    }

    /// forge-config: default.isolate = true
    /// @dev Valuation is a no-op (the adapter accrued the vault before the take), the adapter cannot be valued on
    /// its own, deposits and withdrawals go through at the snapshot price, same-market mutations are blocked.
    function testCbVaultAndAdapterReentry() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Market memory market = initial.market;
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.exec(address(realVault), abi.encodeCall(realVault.deposit, (1e18, address(buyer))));
        uint256 sharesBefore = realVault.balanceOf(address(buyer));

        buyer.push(address(realVault), abi.encodeCall(IVaultV2.accrueInterest, ()), bytes4(0));
        buyer.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.OtherSellInProgress.selector
        );
        buyer.push(address(realVault), abi.encodeCall(realVault.deposit, (1e18, address(buyer))), bytes4(0));
        buyer.push(
            address(realVault), abi.encodeCall(realVault.withdraw, (0.5e18, address(buyer), address(buyer))), bytes4(0)
        );
        (Offer memory nested, bytes memory nestedData) = callbackOffer(market, 1e18, buyer);
        buyer.push(
            address(realVault),
            abi.encodeCall(
                IVaultV2.forceDeallocate, (address(adapter), abi.encode(nested, nestedData), 1e18, address(buyer))
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        buyer.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapter.withdrawToVault, (market, 0)),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory adapterBuy = makeBuyOffer(7 days, 1e18, MAX_TICK);
        adapterBuy.market = market;
        adapterBuy.group = bytes32("nested purchase");
        buyer.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    adapterBuy,
                    sign([adapterBuy], signerAllocator),
                    adapterBuy.maxUnits,
                    address(buyer),
                    address(buyer),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        buyer.push(address(adapter), abi.encodeCall(IMidnightAdapter.updateDurationCaps, (market.maturity)), bytes4(0));

        callbackForceDeallocate(market, 4e18, buyer);
        assertTrue(buyer.called(), "callback ran");

        bytes32 marketId = _marketId(market);
        assertEq(adapter.netCredit(marketId), 4e18, "netCredit");
        assertEq(realVault.allocation(adapter.adapterId()), 4e18, "adapter id");
        assertEq(realVault.allocation(durationId(1 days)), 4e18, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 4e18, "7 days");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter holds nothing");
        // 10 initial + 1 pre-deposit + 1 callback deposit - 0.5 callback withdraw + 4 sold ... - 4 credit
        assertEq(backing(), 11.5e18, "backing");
        assertEq(realVault.totalAssets(), 11.5e18 - 0.08e18, "totalAssets net of the penalty");
        // The callback depositor got exactly what it paid for.
        assertApproxEqAbs(
            realVault.previewRedeem(realVault.balanceOf(address(buyer)) - sharesBefore), 0.5e18, 1, "no free shares"
        );
    }

    /// forge-config: default.isolate = true
    /// @dev A nested forceDeallocate on another market completes inside the callback; both sales are accounted.
    function testCbNestedForceDeallocateOtherMarket() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory other = buyOnRealVault(6 days, 1e18);
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.exec(address(realVault), abi.encodeCall(realVault.deposit, (1e18, address(buyer))));

        (Offer memory nested, bytes memory nestedData) = callbackOffer(other.market, 1e18, buyer);
        buyer.push(
            address(realVault),
            abi.encodeCall(
                IVaultV2.forceDeallocate, (address(adapter), abi.encode(nested, nestedData), 1e18, address(buyer))
            ),
            bytes4(0)
        );

        callbackForceDeallocate(initial.market, 4e18, buyer);
        assertTrue(buyer.called(), "callback ran");

        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18, "netCredit initial");
        assertEq(adapter.netCredit(_marketId(other.market)), 0, "netCredit other");
        assertEq(adapter.marketIdsLength(), 1, "markets");
        assertEq(realVault.allocation(adapter.adapterId()), 4e18, "adapter id");
        assertEq(realVault.allocation(durationId(1 days)), 4e18, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 4e18, "7 days");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter holds nothing");
        assertEq(loanToken.balanceOf(address(realVault)), 1e18 + 1e18 + 1e18 + 4e18, "idle");
        assertEq(backing(), 11e18, "backing");
        assertEq(realVault.totalAssets(), 11e18 - 0.02e18 - 0.08e18, "totalAssets net of penalties");
    }

    /// forge-config: default.isolate = true
    /// @dev The adapter can buy on another market inside the callback (the vault is already accrued).
    function testCbNestedAdapterBuyOtherMarket() public {
        Offer memory initial = freshPosition(MAX_TICK);
        ForceDeallocateBuyer buyer = newBuyer();
        Offer memory adapterBuy = makeBuyOffer(6 days, 1e18, MAX_TICK);
        deal(storedCollaterals[0].token, address(buyer), 10e18);
        buyer.exec(storedCollaterals[0].token, abi.encodeCall(IERC20.approve, (address(midnight), type(uint256).max)));
        buyer.exec(
            address(midnight), abi.encodeCall(IMidnight.supplyCollateral, (adapterBuy.market, 0, 2e18, address(buyer)))
        );
        buyer.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    adapterBuy,
                    sign([adapterBuy], signerAllocator),
                    adapterBuy.maxUnits,
                    address(buyer),
                    address(buyer),
                    address(0),
                    ""
                )
            ),
            bytes4(0)
        );

        callbackForceDeallocate(initial.market, 4e18, buyer);
        assertTrue(buyer.called(), "callback ran");

        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18, "netCredit initial");
        assertEq(adapter.netCredit(_marketId(adapterBuy.market)), 1e18, "netCredit bought");
        assertEq(realVault.allocation(adapter.adapterId()), 5e18, "adapter id");
        assertEq(realVault.allocation(durationId(1 days)), 5e18, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 4e18, "7 days");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter holds nothing");
        assertEq(loanToken.balanceOf(address(realVault)), 2e18 - 1e18 + 4e18, "idle");
        assertEq(backing(), 10e18, "backing");
    }

    /// forge-config: default.isolate = true
    /// @dev Realizing a default inside the callback and exiting at the snapshot price gives the same result as
    /// doing it without any callback (see testNoCbAccrueLiquidateRedeem): the callback adds nothing.
    function testCbLossDuringForceDeallocateThenRedeem() public {
        Offer memory initial = freshPosition(MAX_TICK);
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.exec(address(realVault), abi.encodeCall(realVault.deposit, (2e18, address(buyer))));
        uint256 buyerBalanceBefore = loanToken.balanceOf(address(buyer));
        uint256 buyerShares = realVault.balanceOf(address(buyer));

        buyer.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        buyer.push(
            address(realVault),
            abi.encodeCall(realVault.redeem, (buyerShares, address(buyer), address(buyer))),
            bytes4(0)
        );

        callbackForceDeallocate(initial.market, 1e15, buyer);
        assertTrue(buyer.called(), "callback ran");

        // Exited whole at the pre-loss price (minus the 1e15 paid for the credit bought).
        assertEq(loanToken.balanceOf(address(buyer)), buyerBalanceBefore + 2e18 - 1e15, "buyer proceeds");
        assertEq(realVault.totalAssets(), backing(), "loss visible after the tx");
        assertEq(realVault.allocation(adapter.adapterId()), adapter.netCredit(_marketId(initial.market)), "caps");
        assertApproxEqAbs(backing(), 10e18 - 4e18 + 1e15 / 2, 2, "half of the remaining credit is lost");
    }

    /// forge-config: default.isolate = true
    /// @dev Baseline without any callback: accrue, realize a default, redeem in one transaction exits at the pre-loss
    /// price. This is a property of the vault's once-per-transaction accrual, not of callbacks.
    function testNoCbAccrueLiquidateRedeem() public {
        Offer memory initial = freshPosition(MAX_TICK);
        address exiter = makeAddr("exiter");
        deal(address(loanToken), exiter, 2e18);
        vm.startPrank(exiter);
        loanToken.approve(address(realVault), type(uint256).max);
        realVault.deposit(2e18, exiter);
        vm.stopPrank();
        uint256 exiterShares = realVault.balanceOf(exiter);

        this.accrueLiquidateRedeem(initial.market, exiter, exiterShares);

        assertEq(loanToken.balanceOf(exiter), 2e18, "exited whole");
        assertEq(realVault.totalAssets(), backing(), "loss visible after the tx");
        assertApproxEqAbs(backing(), 10e18 - 4e18, 2, "half of the credit is lost");
    }

    function accrueLiquidateRedeem(Market memory market, address exiter, uint256 shares) external {
        realVault.accrueInterest();
        this.realizeDefault(market, ORACLE_PRICE_SCALE / 2);
        vm.prank(exiter);
        realVault.redeem(shares, exiter, exiter);
    }

    /// forge-config: default.isolate = true
    /// @dev Dropping a stale duration id inside the callback: the outer sale then reports ids without it.
    function testCbUpdateDurationCapsDuringSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        skip(1);
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.push(
            address(adapter), abi.encodeCall(IMidnightAdapter.updateDurationCaps, (initial.market.maturity)), bytes4(0)
        );

        callbackForceDeallocate(initial.market, 4e18, buyer);
        assertTrue(buyer.called(), "callback ran");

        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18, "netCredit");
        assertEq(adapter.maturityDurationCount(initial.market.maturity), 1, "duration count");
        assertEq(realVault.allocation(adapter.adapterId()), 4e18, "adapter id");
        assertEq(realVault.allocation(durationId(1 days)), 4e18, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days dropped");
        assertEq(backing(), 10e18, "backing");
    }

    /// forge-config: default.isolate = true
    /// @dev Full sales on both markets, the nested one first: both markets leave the adapter's list.
    function testCbFullSalesPopMarkets() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory other = buyOnRealVault(6 days, 1e18);
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.exec(address(realVault), abi.encodeCall(realVault.deposit, (1e18, address(buyer))));
        assertEq(adapter.marketIdsLength(), 2, "two markets");

        (Offer memory nested, bytes memory nestedData) = callbackOffer(other.market, 1e18, buyer);
        buyer.push(
            address(realVault),
            abi.encodeCall(
                IVaultV2.forceDeallocate, (address(adapter), abi.encode(nested, nestedData), 1e18, address(buyer))
            ),
            bytes4(0)
        );

        callbackForceDeallocate(initial.market, 8e18, buyer);
        assertTrue(buyer.called(), "callback ran");

        assertEq(adapter.marketIdsLength(), 0, "no markets left");
        assertEq(adapter.netCredit(_marketId(initial.market)), 0, "netCredit initial");
        assertEq(adapter.netCredit(_marketId(other.market)), 0, "netCredit other");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(adapter.realAssets(), 0, "realAssets");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter holds nothing");
        assertEq(loanToken.balanceOf(address(realVault)), 11e18, "everything is idle");
        assertEq(realVault.totalAssets(), 11e18 - 0.02e18 - 0.16e18, "totalAssets net of penalties");
    }

    /// forge-config: default.isolate = true
    /// @dev A discounted offer with a callback: the buyer pays the discounted price to the caller, the caller pays
    /// the full amount to the vault.
    function testCbDiscountedOffer() public {
        Offer memory initial = freshPosition(MAX_TICK);
        ForceDeallocateBuyer buyer = newBuyer();
        buyer.push(address(realVault), abi.encodeCall(realVault.deposit, (1e18, address(buyer))), bytes4(0));
        (Offer memory offer, bytes memory ratifierData_) = callbackOffer(initial.market, 2e18, buyer, discountTick);
        uint256 received = uint256(2e18).mulDivDown(TickLib.tickToPrice(discountTick), 1e18);
        deal(address(loanToken), address(this), 2e18 - received);
        loanToken.approve(address(adapter), 2e18);
        uint256 buyerBalanceBefore = loanToken.balanceOf(address(buyer));

        realVault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData_), 2e18, address(this));
        assertTrue(buyer.called(), "callback ran");

        assertEq(loanToken.balanceOf(address(this)), 0, "caller paid the discount");
        assertEq(
            loanToken.balanceOf(address(buyer)), buyerBalanceBefore - received - 1e18, "buyer paid price + deposit"
        );
        assertEq(loanToken.balanceOf(address(realVault)), 2e18 + 1e18 + 2e18, "idle");
        assertEq(adapter.netCredit(_marketId(initial.market)), 6e18, "netCredit");
        assertEq(realVault.allocation(adapter.adapterId()), 6e18, "adapter id");
        assertEq(backing(), 11e18, "backing");
    }

    /// forge-config: default.isolate = true
    /// @dev The callback is the payer, and the adapter has a max approval to Midnight: it must refuse to be the
    /// callback of an offer it did not make.
    function testCbAdapterAsCallbackReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        ForceDeallocateBuyer buyer = newBuyer();
        (Offer memory offer, bytes memory ratifierData_) = callbackOffer(initial.market, 1e18, buyer);
        offer.callback = address(adapter);
        bytes32 root_ = HashLib.hashOffer(offer);
        buyer.exec(
            address(buyerRatifier), abi.encodeCall(SetterRatifier.setIsRootRatified, (address(buyer), root_, true))
        );
        ratifierData_ = abi.encode(root_, uint256(0), new bytes32[](0));

        vm.expectRevert(IMidnightAdapter.NotSelf.selector);
        realVault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData_), 1e18, address(this));
    }

    /// forge-config: default.isolate = true
    /// @dev The callback cannot collateralize or repay on behalf of the adapter, so overselling still leaves the
    /// adapter unhealthy at the end of the take.
    function testCbOversellStillReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        ForceDeallocateBuyer buyer = newBuyer();
        deal(storedCollaterals[0].token, address(buyer), 10e18);
        buyer.exec(storedCollaterals[0].token, abi.encodeCall(IERC20.approve, (address(midnight), type(uint256).max)));
        buyer.push(
            address(midnight),
            abi.encodeCall(IMidnight.supplyCollateral, (initial.market, 0, 2e18, address(adapter))),
            IMidnight.Unauthorized.selector
        );
        buyer.push(
            address(midnight),
            abi.encodeCall(IMidnight.repay, (initial.market, 1e18, address(adapter), address(0), "")),
            IMidnight.Unauthorized.selector
        );

        (Offer memory offer, bytes memory ratifierData_) = callbackOffer(initial.market, 9e18, buyer);
        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        realVault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData_), 9e18, address(this));
    }
}
