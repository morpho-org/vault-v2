// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MorphoBlueAdapter} from "../src/adapters/MorphoBlueAdapter.sol";
import {MorphoBlueAdapterFactory} from "../src/adapters/MorphoBlueAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IrmMock} from "../lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMorphoBlueAdapter} from "../src/adapters/interfaces/IMorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "../src/adapters/interfaces/IMorphoBlueAdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MorphoBlueAdapterTest is Test {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;

    MorphoBlueAdapterFactory internal factory;
    MorphoBlueAdapter internal adapter;
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
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

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
        factory = new MorphoBlueAdapterFactory();
        adapter =
            MorphoBlueAdapter(factory.createMorphoBlueAdapter(address(parentVault), address(morpho), address(irm)));

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
        vm.expectRevert(IMorphoBlueAdapter.NotAuthorized.selector);
        adapter.allocate(abi.encode(marketParams), assets);
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundAssets(assets);
        vm.expectRevert(IMorphoBlueAdapter.NotAuthorized.selector);
        adapter.deallocate(abi.encode(marketParams), assets);
    }

    function testAllocateDifferentAssetReverts(address randomAsset, uint256 assets) public {
        vm.assume(randomAsset != marketParams.loanToken);
        assets = _boundAssets(assets);
        marketParams.loanToken = randomAsset;
        vm.expectRevert(IMorphoBlueAdapter.LoanAssetMismatch.selector);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), assets);
    }

    function testDeallocateDifferentAssetReverts(address randomAsset, uint256 assets) public {
        vm.assume(randomAsset != marketParams.loanToken);
        assets = _boundAssets(assets);
        marketParams.loanToken = randomAsset;
        vm.expectRevert(IMorphoBlueAdapter.LoanAssetMismatch.selector);
        vm.prank(address(parentVault));
        adapter.deallocate(abi.encode(marketParams), assets);
    }

    function testAllocate(uint256 assets) public {
        assets = _boundAssets(assets);
        deal(address(loanToken), address(adapter), assets);

        vm.prank(address(parentVault));
        (bytes32[] memory ids, int256 change) = adapter.allocate(abi.encode(marketParams), assets);

        assertEq(adapter.assetsInMarket(marketId), assets, "Incorrect assetsInMarket");
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), assets, "Incorrect assets in Morpho");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(uint256(change), assets, "Incorrect change");
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
        (bytes32[] memory ids, int256 change) = adapter.deallocate(abi.encode(marketParams), withdrawAssets);

        assertEq(adapter.assetsInMarket(marketId), initialAssets - withdrawAssets, "Incorrect assetsInMarket");
        uint256 afterSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(afterSupply, initialAssets - withdrawAssets, "Supply not decreased correctly");
        assertEq(loanToken.balanceOf(address(adapter)), withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(uint256(-change), withdrawAssets, "Incorrect change");
    }

    function testFactoryCreateMorphoBlueAdapter() public {
        address newParentVaultAddr =
            address(new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0)));

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(MorphoBlueAdapter).creationCode, abi.encode(newParentVaultAddr, morpho, irm))
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit IMorphoBlueAdapterFactory.CreateMorphoBlueAdapter(newParentVaultAddr, expectedNewAdapter);

        address newAdapter = factory.createMorphoBlueAdapter(newParentVaultAddr, address(morpho), address(irm));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MorphoBlueAdapter(newAdapter).parentVault(), newParentVaultAddr, "Incorrect parent vault");
        assertEq(MorphoBlueAdapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(
            factory.morphoBlueAdapter(newParentVaultAddr, address(morpho), address(irm)),
            newAdapter,
            "Adapter not tracked correctly"
        );
        assertTrue(factory.isMorphoBlueAdapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IMorphoBlueAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit IMorphoBlueAdapter.SetSkimRecipient(newRecipient);
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
        emit IMorphoBlueAdapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        vm.expectRevert(IMorphoBlueAdapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }

    function testLossRealization(uint256 initial, uint256 expectedLoss, uint256 interest) public {
        initial = _boundAssets(initial);
        expectedLoss = bound(expectedLoss, 0, initial / 2);
        interest = bound(interest, 0, initial);

        // Setup
        deal(address(loanToken), address(adapter), initial);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), initial);
        assertEq(adapter.assetsInMarket(marketId), initial, "Initial assetsInMarket incorrect");
        _overrideMarketTotalSupplyAssets(-int256(expectedLoss));
        bytes32[] memory ids;
        int256 change;

        // Realize loss
        uint256 snapshot = vm.snapshotState();
        vm.prank(address(parentVault));
        (ids, change) = adapter.deallocate(abi.encode(marketParams), 0);
        assertEq(ids, expectedIds, "ids: realizeLoss");
        assertEq(uint256(-change), expectedLoss, "loss: realizeLoss");
        assertEq(
            adapter.assetsInMarket(marketId),
            morpho.expectedSupplyAssets(marketParams, address(adapter)),
            "assetsInMarket: realizeLoss: 1"
        );

        // Can't realize twice
        vm.prank(address(parentVault));
        (ids, change) = adapter.deallocate(abi.encode(marketParams), 0);
        assertEq(ids, expectedIds, "ids: interest");
        assertEq(uint256(change), 0, "interest: interest");
        assertEq(
            adapter.assetsInMarket(marketId),
            morpho.expectedSupplyAssets(marketParams, address(adapter)),
            "assetsInMarket: interest"
        );

        // Interest covers the loss.
        vm.revertToState(snapshot);
        _overrideMarketTotalSupplyAssets(int256(interest));
        vm.prank(address(parentVault));
        (ids, change) = adapter.deallocate(abi.encode(marketParams), 0);
        assertEq(ids, expectedIds, "ids: interest");
        assertApproxEqAbs(change, int256(interest) - int256(expectedLoss), 1, "interest: interest");
        assertEq(
            adapter.assetsInMarket(marketId),
            morpho.expectedSupplyAssets(marketParams, address(adapter)),
            "assetsInMarket: interest"
        );
    }

    function testWrongIrm(address randomIrm) public {
        vm.assume(randomIrm != address(irm));
        marketParams.irm = randomIrm;
        vm.expectRevert(IMorphoBlueAdapter.IrmMismatch.selector);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), 0);

        vm.prank(address(parentVault));
        vm.expectRevert(IMorphoBlueAdapter.IrmMismatch.selector);
        adapter.deallocate(abi.encode(marketParams), 0);
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

    function testIds() public view {
        assertEq(adapter.ids(marketParams), expectedIds);
    }

    function testDonationResistance(uint256 deposit, uint256 donation) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        donation = bound(donation, 1, MAX_TEST_ASSETS);

        // Deposit some assets
        deal(address(loanToken), address(adapter), deposit * 2);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), deposit);

        uint256 sharesInMarket = MorphoLib.supplyShares(morpho, marketId, address(adapter));
        assertEq(adapter.sharesInMarket(marketId), sharesInMarket, "shares not recorded");

        // Donate to adapter
        address donor = makeAddr("donor");
        deal(address(loanToken), donor, donation);
        vm.startPrank(donor);
        loanToken.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams, donation, 0, address(adapter), "");
        vm.stopPrank();

        // Test no impact on allocation
        uint256 oldAssetsInMarket = adapter.assetsInMarket(marketId);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), deposit);
        assertEq(adapter.assetsInMarket(marketId), oldAssetsInMarket + deposit, "assets have changed");
    }
}
