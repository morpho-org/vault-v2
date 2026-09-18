// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapterFactory} from "../src/adapters/MidnightAdapterFactory.sol";
import {IMidnightAdapter, AUCTION_DELAY, AUCTION_DURATION} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {IRatifier} from "../lib/midnight/src/interfaces/IRatifier.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IMidnight, Offer, Market, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS, DEFAULT_TICK_SPACING} from "../lib/midnight/src/libraries/ConstantsLib.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";

contract MidnightAdapterWithdrawForTest is Test, IRatifier {
    using MathLib for uint256;

    IMidnight internal midnight;
    IMidnightAdapter internal adapter;
    MidnightAdapterFactory internal factory;
    VaultV2Mock internal vault;
    IERC20 internal loanToken;
    IERC20 internal collateralToken;

    address internal curator = makeAddr("curator");
    address internal allocator = makeAddr("allocator");
    address internal borrower = makeAddr("borrower");
    address internal liquidator = makeAddr("liquidator");

    function setUp() public {
        vm.setEvmVersion("osaka");
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);

        loanToken = IERC20(address(new ERC20Mock(18)));
        collateralToken = IERC20(address(new ERC20Mock(18)));
        vault = new VaultV2Mock(address(loanToken), makeAddr("owner"), curator, allocator, address(0));

        uint256[] memory durations = new uint256[](1);
        durations[0] = 7 days;
        factory = new MidnightAdapterFactory(durations);
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(vault), address(midnight)));

        bytes memory data = abi.encodeCall(IMidnightAdapter.addSubRatifier, (address(this)));
        vm.prank(curator);
        adapter.submit(data);
        adapter.addSubRatifier(address(this));

        address[] memory adapters = new address[](1);
        adapters[0] = address(adapter);
        vault.setAdapters(adapters);
        vault.setAdaptersLength(1);
        deal(address(loanToken), address(vault), 10e18);

        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), type(uint256).max);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.stopPrank();

        vm.prank(liquidator);
        loanToken.approve(address(midnight), type(uint256).max);
    }

    function testWithdrawForBeforeAuctionReverts(uint256 timestamp) public {
        Market memory market = _market();
        _lend(market);
        vm.warp(bound(timestamp, block.timestamp, market.maturity + AUCTION_DELAY - 1));

        vm.expectRevert(stdError.arithmeticError);
        adapter.withdrawFor(market, 0.5e18, liquidator, abi.encode(borrower, _repayCall(market, 0.5e18)));
    }

    function testWithdrawForPrice(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, AUCTION_DURATION * 3 / 2);
        Market memory market = _market();
        _lend(market);
        vm.warp(market.maturity + AUCTION_DELAY + elapsed);
        uint256 expectedVaultAssets = uint256(0.5e18).mulDivUp(AUCTION_DURATION.zeroFloorSub(elapsed), AUCTION_DURATION);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(vault));

        adapter.withdrawFor(market, 0.5e18, liquidator, abi.encode(borrower, _repayCall(market, 0.5e18)));

        assertEq(loanToken.balanceOf(address(vault)), vaultBalanceBefore + expectedVaultAssets, "vault balance");
        assertEq(loanToken.balanceOf(liquidator), 0.5e18 - expectedVaultAssets, "receiver balance");
        assertEq(midnight.credit(IdLib.toId(market), address(adapter)), 0.5e18, "adapter credit");
    }

    function testWithdrawForAtAuctionStart() public {
        testWithdrawForPrice(0);
    }

    function testWithdrawForAtAuctionLastSecond() public {
        testWithdrawForPrice(AUCTION_DURATION - 1);
    }

    function testWithdrawForAtAuctionEnd() public {
        testWithdrawForPrice(AUCTION_DURATION);
    }

    function testWithdrawForAfterAuctionEnd() public {
        testWithdrawForPrice(AUCTION_DURATION + 1);
    }

    function testWithdrawForWithdrawsExistingLiquidityAtPar() public {
        Market memory market = _market();
        _lend(market);
        vm.prank(borrower);
        midnight.repay(market, 0.5e18, borrower, address(0), bytes(""));
        vm.warp(market.maturity + AUCTION_DELAY + AUCTION_DURATION / 2);

        // The existing liquidity goes to the vault at par, so nothing is left without liquidity added in the callback.
        vm.expectRevert(stdError.arithmeticError);
        adapter.withdrawFor(market, 0.25e18, liquidator, abi.encode(address(0), bytes("")));

        uint256 vaultBalanceBefore = loanToken.balanceOf(address(vault));
        adapter.withdrawFor(market, 0.5e18, liquidator, abi.encode(borrower, _repayCall(market, 0.5e18)));
        assertEq(
            loanToken.balanceOf(address(vault)), vaultBalanceBefore + 0.5e18 + 0.25e18, "existing liquidity at par"
        );
        assertEq(loanToken.balanceOf(liquidator), 0.25e18, "rebate on added liquidity only");
    }

    function testWithdrawForAfterPostMaturityLiquidation() public {
        uint256 units = 0.5e18;
        Market memory market = _market();
        bytes32 marketId = IdLib.toId(market);
        _lend(market);

        // Let the auction fall from par to 60%.
        vm.warp(market.maturity + AUCTION_DELAY + AUCTION_DURATION * 40 / 100);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(vault));

        // Post-maturity liquidation repays 0.5 debt and makes 0.5 loan tokens withdrawable.
        deal(address(loanToken), liquidator, units);
        bytes memory liquidateCall = abi.encodeCall(
            IMidnight.liquidate, (market, 0, 0, units, borrower, true, liquidator, address(0), bytes(""))
        );
        adapter.withdrawFor(market, units, liquidator, abi.encode(liquidator, liquidateCall));

        assertEq(loanToken.balanceOf(address(vault)), vaultBalanceBefore + 0.3e18, "vault receives the auction price");
        assertEq(loanToken.balanceOf(liquidator), 0.2e18, "liquidator receives the discount");
        assertEq(midnight.credit(marketId, liquidator), 0, "entering the market was unnecessary");
        assertEq(midnight.credit(marketId, address(adapter)), 0.5e18, "adapter redeemed its own credit");
        assertEq(midnight.withdrawable(marketId), 0, "liquidation proceeds were withdrawn");
        assertEq(adapter.lossAllowance(marketId), 0, "no allowance needed");
    }

    function testWithdrawForBypassesEnterGate() public {
        Market memory market = _market();
        market.enterGate = address(this);
        _lend(market);
        vm.warp(market.maturity + AUCTION_DELAY + AUCTION_DURATION / 2);

        Offer memory offer = _buyOffer(market);
        offer.buy = false;
        offer.group = keccak256("sell");
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.tick = TickLib.priceToTick(0.5e18, DEFAULT_TICK_SPACING);
        vm.prank(liquidator);
        vm.expectRevert(IMidnight.BuyerGatedFromIncreasingCredit.selector);
        midnight.take(
            offer, abi.encode(address(this), bytes("")), 0.5e18, liquidator, address(0), address(0), bytes("")
        );

        adapter.withdrawFor(market, 0.5e18, liquidator, abi.encode(borrower, _repayCall(market, 0.5e18)));
        assertEq(loanToken.balanceOf(liquidator), 0.25e18);
    }

    /// @dev Enter gate that only lets the adapter increase its credit.
    function canIncreaseCredit(address account) external view returns (bool) {
        return account == address(adapter);
    }

    function canIncreaseDebt(address) external pure returns (bool) {
        return true;
    }

    function isRatified(Offer memory, bytes memory, address) public pure override returns (bytes32) {
        return CALLBACK_SUCCESS;
    }

    /// @dev Adds liquidity with a call to Midnight.
    function onWithdrawFor(bytes memory data) external {
        (address sender, bytes memory midnightCall) = abi.decode(data, (address, bytes));
        if (midnightCall.length == 0) return;
        vm.prank(sender);
        (bool success,) = address(midnight).call(midnightCall);
        require(success, "midnight call failed");
    }

    function _repayCall(Market memory market, uint256 units) internal view returns (bytes memory) {
        return abi.encodeCall(IMidnight.repay, (market, units, borrower, address(0), bytes("")));
    }

    function _buyOffer(Market memory market) internal view returns (Offer memory) {
        return Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: block.timestamp,
            tick: MAX_TICK,
            group: keccak256(abi.encode("buy", IdLib.toId(market))),
            callback: address(adapter),
            callbackData: bytes(""),
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: 1e18,
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
    }

    function _lend(Market memory market) internal {
        Offer memory offer = _buyOffer(market);
        deal(address(collateralToken), borrower, 1e18);
        vm.startPrank(borrower);
        midnight.supplyCollateral(market, 0, 1e18, borrower);
        midnight.take(offer, abi.encode(address(this), bytes("")), 1e18, borrower, borrower, address(0), bytes(""));
        vm.stopPrank();
    }

    function _market() internal returns (Market memory market) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        OracleMock oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken), lltv: 1e18, liquidationCursor: 0.25e18, oracle: address(oracle)
        });
        market = Market({
            chainId: block.chainid,
            midnight: address(midnight),
            loanToken: address(loanToken),
            collateralParams: collateralParams,
            maturity: block.timestamp + 7 days,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }
}
