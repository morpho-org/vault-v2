// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MorphoMarketV1Adapter} from "../src/adapters/MorphoMarketV1Adapter.sol";
import {MorphoMarketV1AdapterFactory} from "../src/adapters/MorphoMarketV1AdapterFactory.sol";
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
import {IMorphoMarketV1Adapter} from "../src/adapters/interfaces/IMorphoMarketV1Adapter.sol";
import {IMorphoMarketV1AdapterFactory} from "../src/adapters/interfaces/IMorphoMarketV1AdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MorphoMarketV1AdapterTest is Test {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;

    MorphoMarketV1AdapterFactory internal factory;
    MorphoMarketV1Adapter internal adapter;
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

        loanToken = new ERC20Mock(18);
        collateralToken = new ERC20Mock(18);
        rewardToken = new ERC20Mock(18);
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
        factory = new MorphoMarketV1AdapterFactory();
        adapter = MorphoMarketV1Adapter(factory.createMorphoMarketV1Adapter(address(parentVault), address(morpho)));

        expectedIds = new bytes32[](3);
        expectedIds[0] = keccak256(abi.encode("this", address(adapter)));
        expectedIds[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        expectedIds[2] = keccak256(abi.encode("this/marketParams", address(adapter), marketParams));
    }

    function _boundAssets(uint256 assets) internal pure returns (uint256) {
        return bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
    }

    function testFactoryAndParentVaultAndMorphoSet() public view {
        assertEq(adapter.factory(), address(factory), "Incorrect factory set");
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.morpho(), address(morpho), "Incorrect morpho set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundAssets(assets);
        vm.expectRevert(IMorphoMarketV1Adapter.NotAuthorized.selector);
        adapter.allocate(abi.encode(marketParams), assets, bytes4(0), address(0));
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundAssets(assets);
        vm.expectRevert(IMorphoMarketV1Adapter.NotAuthorized.selector);
        adapter.deallocate(abi.encode(marketParams), assets, bytes4(0), address(0));
    }

    function testAllocateDifferentAssetReverts(address randomAsset, uint256 assets) public {
        vm.assume(randomAsset != marketParams.loanToken);
        assets = _boundAssets(assets);
        marketParams.loanToken = randomAsset;
        vm.expectRevert(IMorphoMarketV1Adapter.LoanAssetMismatch.selector);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), assets, bytes4(0), address(0));
    }

    function testDeallocateDifferentAssetReverts(address randomAsset, uint256 assets) public {
        vm.assume(randomAsset != marketParams.loanToken);
        assets = _boundAssets(assets);
        marketParams.loanToken = randomAsset;
        vm.expectRevert(IMorphoMarketV1Adapter.LoanAssetMismatch.selector);
        vm.prank(address(parentVault));
        adapter.deallocate(abi.encode(marketParams), assets, bytes4(0), address(0));
    }

    function testAllocate(uint256 assets) public {
        assets = _boundAssets(assets);
        deal(address(loanToken), address(adapter), assets);

        (bytes32[] memory ids, uint256 interest) =
            parentVault.allocateMocked(address(adapter), abi.encode(marketParams), assets);

        assertEq(adapter.allocation(marketParams), assets, "Incorrect allocation");
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), assets, "Incorrect assets in Morpho");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Interest should be zero");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = _boundAssets(initialAssets);
        withdrawAssets = bound(withdrawAssets, 1, initialAssets);

        deal(address(loanToken), address(adapter), initialAssets);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), initialAssets);

        uint256 beforeSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(beforeSupply, initialAssets, "Precondition failed: supply not set");

        (bytes32[] memory ids, uint256 interest) =
            parentVault.deallocateMocked(address(adapter), abi.encode(marketParams), withdrawAssets);

        assertEq(interest, 0, "Interest should be zero");
        assertEq(adapter.allocation(marketParams), initialAssets - withdrawAssets, "Incorrect allocation");
        uint256 afterSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(afterSupply, initialAssets - withdrawAssets, "Supply not decreased correctly");
        assertEq(loanToken.balanceOf(address(adapter)), withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids.length, expectedIds.length, "Unexpected number of ids returned");
        assertEq(ids, expectedIds, "Incorrect ids returned");
    }

    function testFactoryCreateMorphoMarketV1Adapter() public {
        address newParentVaultAddr =
            address(new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0)));

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(MorphoMarketV1Adapter).creationCode, abi.encode(newParentVaultAddr, morpho))
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit IMorphoMarketV1AdapterFactory.CreateMorphoMarketV1Adapter(newParentVaultAddr, expectedNewAdapter);

        address newAdapter = factory.createMorphoMarketV1Adapter(newParentVaultAddr, address(morpho));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MorphoMarketV1Adapter(newAdapter).parentVault(), newParentVaultAddr, "Incorrect parent vault");
        assertEq(MorphoMarketV1Adapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(
            factory.morphoMarketV1Adapter(newParentVaultAddr, address(morpho)),
            newAdapter,
            "Adapter not tracked correctly"
        );
        assertTrue(factory.isMorphoMarketV1Adapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IMorphoMarketV1Adapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit IMorphoMarketV1Adapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);

        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = _boundAssets(assets);

        ERC20Mock token = new ERC20Mock(18);

        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        vm.expectEmit();
        emit IMorphoMarketV1Adapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        vm.expectRevert(IMorphoMarketV1Adapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }

    function testLossRealizationNotMocked(address rdmToken) public {
        vm.assume(rdmToken != address(loanToken));
        vm.expectRevert(IMorphoMarketV1Adapter.LoanAssetMismatch.selector);
        MarketParams memory rdmMarketParams = marketParams;
        rdmMarketParams.loanToken = rdmToken;
        adapter.realizeLoss(abi.encode(rdmMarketParams), bytes4(0), rdmToken);

        adapter.realizeLoss(abi.encode(marketParams), bytes4(0), address(0));
    }

    function testLossRealizationImpossible(uint256 deposit) public {
        deposit = _boundAssets(deposit);

        // Setup
        deal(address(loanToken), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);
        _overrideMarketTotalSupplyAssets(2);

        // Realize loss.
        vm.expectRevert(stdError.arithmeticError);
        parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
    }

    function testLossRealizationZero(uint256 deposit) public {
        deposit = _boundAssets(deposit);

        // Setup.
        deal(address(loanToken), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, 0, "loss");
        assertEq(adapter.allocation(marketParams), deposit, "allocation");
    }

    function testLossRealization(uint256 deposit, uint256 _loss) public {
        deposit = _boundAssets(deposit);
        _loss = bound(_loss, 1, deposit);

        // Setup.
        deal(address(loanToken), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);
        _overrideMarketTotalSupplyAssets(-int256(_loss));

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(marketParams), deposit - _loss, "allocation");
    }

    function testLossRealizationAfterAllocate(uint256 deposit1, uint256 _loss, uint256 deposit2) public {
        deposit1 = _boundAssets(deposit1);
        _loss = bound(_loss, 1, deposit1 / 2); // Limit the loss to avoid the share price to explode.
        deposit2 = bound(deposit2, 0, MAX_TEST_ASSETS);

        // Setup.
        deal(address(loanToken), address(adapter), deposit1 + deposit2);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit1);
        _overrideMarketTotalSupplyAssets(-int256(_loss));

        // Allocate.
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit2);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(marketParams), deposit1 - _loss + deposit2, "allocation");
    }

    function testLossRealizationAfterDeallocate(uint256 initial, uint256 _loss, uint256 withdraw) public {
        initial = _boundAssets(initial);
        _loss = bound(_loss, 1, initial);
        withdraw = bound(withdraw, 0, initial - _loss);

        // Setup.
        deal(address(loanToken), address(adapter), initial);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), initial);
        _overrideMarketTotalSupplyAssets(-int256(_loss));

        // Deallocate.
        parentVault.deallocateMocked(address(adapter), abi.encode(marketParams), withdraw);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(marketParams), initial - _loss - withdraw, "allocation");
    }

    function testLossRealizationAfterInterest(uint256 deposit, uint256 _loss, uint256 interest) public {
        deposit = _boundAssets(deposit);
        _loss = bound(_loss, 1, deposit);
        interest = bound(interest, 0, deposit);

        // Setup.
        deal(address(loanToken), address(adapter), deposit + interest);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);
        uint256 expectedSupplyBefore = morpho.expectedSupplyAssets(marketParams, address(adapter));
        _overrideMarketTotalSupplyAssets(-int256(_loss));

        // Interest covers the loss.
        _overrideMarketTotalSupplyAssets(int256(interest));
        uint256 expectedSupplyAfter = morpho.expectedSupplyAssets(marketParams, address(adapter));
        if (expectedSupplyAfter > expectedSupplyBefore) vm.expectRevert(stdError.arithmeticError);
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), abi.encode(marketParams));
        if (_loss >= interest) {
            assertEq(ids, expectedIds, "ids");
            assertEq(loss, _loss - interest, "loss");
            assertApproxEqAbs(adapter.allocation(marketParams), deposit - _loss + interest, 1, "allocation");
        }
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
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);

        uint256 sharesInMarket = MorphoLib.supplyShares(morpho, marketId, address(adapter));
        assertEq(adapter.shares(marketId), sharesInMarket, "shares not recorded");

        // Donate to adapter
        address donor = makeAddr("donor");
        deal(address(loanToken), donor, donation);
        vm.startPrank(donor);
        loanToken.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams, donation, 0, address(adapter), "");
        vm.stopPrank();

        // Test no impact on allocation
        uint256 oldallocation = adapter.allocation(marketParams);
        parentVault.allocateMocked(address(adapter), abi.encode(marketParams), deposit);
        assertEq(adapter.allocation(marketParams), oldallocation + deposit, "assets have changed");
    }
}
