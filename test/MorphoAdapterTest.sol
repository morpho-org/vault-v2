// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MorphoAdapter} from "../src/adapters/MorphoAdapter.sol";
import {MorphoAdapterFactory} from "../src/adapters/MorphoAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IrmMock} from "lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id, Market} from "lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";
import {IMorphoAdapter} from "src/adapters/interfaces/IMorphoAdapter.sol";
import {IMorphoAdapterFactory} from "src/adapters/interfaces/IMorphoAdapterFactory.sol";

contract MorphoAdapterTest is Test {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    MorphoAdapterFactory internal factory;
    MorphoAdapter internal adapter;
    VaultV2Mock internal parentVault;
    MarketParams internal marketParams;
    Id internal marketId;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    ERC20Mock internal rewardToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMorpho internal morpho;
    address internal owner;
    address internal recipient;
    bytes32[] internal expectedIds;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e18;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        loanToken = new ERC20Mock();
        collateralToken = new ERC20Mock();
        rewardToken = new ERC20Mock();
        oracle = new OracleMock();
        irm = new IrmMock();

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.8 ether
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        vm.stopPrank();

        morpho.createMarket(marketParams);
        marketId = marketParams.id();
        parentVault = new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0));
        factory = new MorphoAdapterFactory(address(morpho));
        adapter = MorphoAdapter(factory.createMorphoAdapter(address(parentVault)));

        expectedIds = new bytes32[](3);
        expectedIds[0] = keccak256(abi.encode("adapter", address(adapter)));
        expectedIds[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        expectedIds[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
    }

    function _boundAssets(uint256 assets) internal pure returns (uint256) {
        return bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
    }

    function testParentVaultAndMorphoSet() public view {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.morpho(), address(morpho), "Incorrect morpho set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundAssets(assets);
        vm.expectRevert(IMorphoAdapter.NotAuthorized.selector);
        adapter.allocate(abi.encode(marketParams), assets);
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundAssets(assets);
        vm.expectRevert(IMorphoAdapter.NotAuthorized.selector);
        adapter.deallocate(abi.encode(marketParams), assets);
    }

    function testAllocate(uint256 assets) public {
        assets = _boundAssets(assets);
        deal(address(loanToken), address(adapter), assets);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocate(abi.encode(marketParams), assets);

        assertEq(adapter.assetsInMarketIfNoLoss(marketId), assets, "Incorrect assetsInMarketIfNoLoss");
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), assets, "Incorrect assets in Morpho");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = _boundAssets(initialAssets);
        withdrawAssets = bound(withdrawAssets, 1, initialAssets);

        deal(address(loanToken), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), initialAssets);

        uint256 beforeSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(beforeSupply, initialAssets, "Precondition failed: supply not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.deallocate(abi.encode(marketParams), withdrawAssets);

        assertEq(
            adapter.assetsInMarketIfNoLoss(marketId), initialAssets - withdrawAssets, "Incorrect assetsInMarketIfNoLoss"
        );
        uint256 afterSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(afterSupply, initialAssets - withdrawAssets, "Supply not decreased correctly");
        assertEq(loanToken.balanceOf(address(adapter)), withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
    }

    function testFactoryCreateMorphoAdapter() public {
        address newParentVaultAddr =
            address(new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0)));

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(MorphoAdapter).creationCode, abi.encode(newParentVaultAddr, morpho)));
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit IMorphoAdapterFactory.CreateMorphoAdapter(newParentVaultAddr, expectedNewAdapter);

        address newAdapter = factory.createMorphoAdapter(newParentVaultAddr);

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MorphoAdapter(newAdapter).parentVault(), newParentVaultAddr, "Incorrect parent vault");
        assertEq(MorphoAdapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(factory.morphoAdapter(newParentVaultAddr), newAdapter, "Adapter not tracked correctly");
        assertTrue(factory.isMorphoAdapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IMorphoAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit IMorphoAdapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);

        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = _boundAssets(assets);

        ERC20Mock token = new ERC20Mock();

        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        vm.expectEmit();
        emit IMorphoAdapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        vm.expectRevert(IMorphoAdapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }

    function testRealizeLossNotAuthorizedReverts() public {
        vm.expectRevert(IMorphoAdapter.NotAuthorized.selector);
        adapter.realizeLoss(abi.encode(marketParams), 0);
    }

    function testLossRealization(uint256 initialAssets, uint256 lossAssets, uint256 realizedLoss) public {
        initialAssets = _boundAssets(initialAssets);
        lossAssets = bound(lossAssets, 1, initialAssets);
        realizedLoss = bound(realizedLoss, 0, lossAssets - 1);

        // Setup: deposit assets
        deal(address(loanToken), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), initialAssets);
        assertEq(adapter.assetsInMarketIfNoLoss(marketId), initialAssets, "Initial assetsInMarket incorrect");

        // Loss detection during allocate
        _overrideMarketTotalSupplyAssets(-int256(lossAssets));
        uint256 snapshot = vm.snapshot();
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), 0);
        assertEq(_loss(), lossAssets, "Assets in market should not change");
        vm.revertTo(snapshot);
        vm.prank(address(parentVault));
        adapter.deallocate(abi.encode(marketParams), 0);
        assertEq(_loss(), lossAssets, "Assets in market should not change");

        // Can't realize too much
        vm.expectRevert(IMorphoAdapter.CannotRealizeAsMuch.selector);
        vm.prank(address(parentVault));
        adapter.realizeLoss(abi.encode(marketParams), lossAssets + 1);

        // Partial realization.
        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.realizeLoss(abi.encode(marketParams), realizedLoss);
        assertEq(_loss(), lossAssets - realizedLoss, "Assets in market should change");
        assertEq(ids, expectedIds, "Incorrect ids returned");

        // Full realization.
        uint256 remainingLoss = _loss();
        vm.prank(address(parentVault));
        ids = adapter.realizeLoss(abi.encode(marketParams), remainingLoss);
        assertEq(_loss(), 0, "Assets in market should be zero");
        assertEq(ids, expectedIds, "Incorrect ids returned");

        // Can't realize loss twice
        vm.prank(address(parentVault));
        vm.expectRevert(IMorphoAdapter.CannotRealizeAsMuch.selector);
        ids = adapter.realizeLoss(abi.encode(marketParams), 1);
    }

    function testCumulativeLossRealization(
        uint256 initialAssets,
        uint256 firstLoss,
        uint256 secondLoss,
        uint256 realizedLoss,
        uint256 depositAssets,
        uint256 withdrawAssets,
        uint256 interest
    ) public {
        initialAssets = _boundAssets(initialAssets);
        firstLoss = bound(firstLoss, 1, initialAssets / 2);
        secondLoss = bound(secondLoss, 0, (initialAssets - firstLoss) / 2);
        depositAssets = _boundAssets(depositAssets);
        withdrawAssets = bound(withdrawAssets, 1, depositAssets);
        interest = bound(interest, 0, firstLoss + secondLoss - 1);
        realizedLoss = bound(realizedLoss, 0, firstLoss + secondLoss - interest - 1);
        // Setup
        deal(address(loanToken), address(adapter), initialAssets + depositAssets);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), initialAssets);

        // First loss
        _overrideMarketTotalSupplyAssets(-int256(firstLoss));
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), 0);
        assertEq(_loss(), firstLoss, "Loss should be tracked");

        // Second loss
        _overrideMarketTotalSupplyAssets(-int256(secondLoss));
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), 0);
        assertEq(_loss(), firstLoss + secondLoss, "Loss should be tracked");

        // Depositing doesn't change the loss tracking
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), depositAssets);
        assertEq(_loss(), firstLoss + secondLoss, "Loss should not change");

        // Withdrawing doesn't change the loss tracking
        vm.prank(address(parentVault));
        adapter.deallocate(abi.encode(marketParams), withdrawAssets);
        assertEq(_loss(), firstLoss + secondLoss, "Loss should not change");

        // Interest cover the loss.
        _overrideMarketTotalSupplyAssets(int256(interest));
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), 0);
        assertApproxEqAbs(_loss(), firstLoss + secondLoss - interest, 1, "Loss should be covered");

        // Can't realize too much
        vm.expectRevert(IMorphoAdapter.CannotRealizeAsMuch.selector);
        vm.prank(address(parentVault));
        adapter.realizeLoss(abi.encode(marketParams), firstLoss + secondLoss - interest + 1);

        // Realize loss
        uint256 finalLoss = firstLoss + secondLoss - interest;
        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.realizeLoss(abi.encode(marketParams), realizedLoss);
        assertEq(_loss(), finalLoss - realizedLoss, "Loss should be zero");
        assertEq(ids, expectedIds, "Incorrect ids returned");
    }

    function _loss() internal view returns (uint256) {
        return adapter.assetsInMarketIfNoLoss(marketId)
            - IMorpho(morpho).expectedSupplyAssets(marketParams, address(adapter));
    }

    function _overrideMarketTotalSupplyAssets(int256 change) internal {
        bytes32 marketSlot0 = keccak256(abi.encode(marketId, 3)); // 3 is the slot of the market mappping.
        bytes32 currentSlot0Value = vm.load(address(morpho), marketSlot0);
        uint256 currentTotalSupplyShares = uint256(currentSlot0Value) >> 128;
        uint256 currentTotalSupplyAssets = uint256(currentSlot0Value) & type(uint256).max;
        bytes32 newSlot0Value =
            bytes32((currentTotalSupplyShares << 128) | uint256(int256(currentTotalSupplyAssets) + change));
        vm.store(address(morpho), marketSlot0, newSlot0Value);
    }

    function testOverwriteMarketTotalSupplyAssets(uint256 newTotalSupplyAssets) public {
        Market memory market = morpho.market(marketId);
        newTotalSupplyAssets = _boundAssets(newTotalSupplyAssets);
        _overrideMarketTotalSupplyAssets(int256(newTotalSupplyAssets));
        assertEq(
            morpho.market(marketId).totalSupplyAssets,
            uint128(newTotalSupplyAssets),
            "Market total supply assets not set correctly"
        );
        assertEq(
            morpho.market(marketId).totalSupplyShares,
            uint128(market.totalSupplyShares),
            "Market total supply shares not set correctly"
        );
        assertEq(
            morpho.market(marketId).totalBorrowShares,
            uint128(market.totalBorrowShares),
            "Market total borrow shares not set correctly"
        );
        assertEq(
            morpho.market(marketId).totalBorrowAssets,
            uint128(market.totalBorrowAssets),
            "Market total borrow assets not set correctly"
        );
    }
}
