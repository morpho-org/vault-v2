// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {MorphoAdapter} from "src/adapters/MorphoAdapter.sol";
import {MorphoAdapterFactory} from "src/adapters/MorphoAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultMock} from "./mocks/VaultV2Mock.sol";
import {IrmMock} from "lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id, Market} from "lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";

contract MorphoAdapterTest is Test {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    MorphoAdapterFactory internal factory;
    MorphoAdapter internal adapter;
    VaultMock internal parentVault;
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

    uint256 internal constant MIN_TEST_AMOUNT = 10;
    uint256 internal constant MAX_TEST_AMOUNT = 1e18;

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
        parentVault = new VaultMock(address(loanToken), owner);
        factory = new MorphoAdapterFactory(address(morpho));
        adapter = MorphoAdapter(factory.createMorphoAdapter(address(parentVault)));
    }

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
    }

    function testParentVaultAndMorphoSet() public view {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.morpho(), address(morpho), "Incorrect morpho set");
    }

    function testAllocateInNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.allocateIn(abi.encode(marketParams), amount);
    }

    function testAllocateOutNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.allocateOut(abi.encode(marketParams), amount);
    }

    function testAllocateInSuppliesAssetsToMorpho(uint256 amount) public {
        amount = _boundAmount(amount);
        deal(address(loanToken), address(adapter), amount);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateIn(abi.encode(marketParams), amount);

        uint256 supplied = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(supplied, amount, "Incorrect supplied amount in Morpho");

        bytes32 expectedId = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testAllocateOutWithdrawsAssetsFromMorpho(uint256 initialAmount, uint256 withdrawAmount) public {
        initialAmount = _boundAmount(initialAmount);
        withdrawAmount = bound(withdrawAmount, 1, initialAmount);

        deal(address(loanToken), address(adapter), initialAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), initialAmount);

        uint256 beforeSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(beforeSupply, initialAmount, "Precondition failed: supply not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateOut(abi.encode(marketParams), withdrawAmount);

        uint256 afterSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(afterSupply, initialAmount - withdrawAmount, "Supply not decreased correctly");

        uint256 adapterBalance = loanToken.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAmount, "Adapter did not receive withdrawn tokens");

        bytes32 expectedId = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testFactoryCreateMorphoAdapter() public {
        address newParentVaultAddr = address(new VaultMock(address(loanToken), owner));

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(MorphoAdapter).creationCode, abi.encode(newParentVaultAddr, morpho)));
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit MorphoAdapterFactory.CreateMorphoAdapter(newParentVaultAddr, expectedNewAdapter);

        address newAdapter = factory.createMorphoAdapter(newParentVaultAddr);

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MorphoAdapter(newAdapter).parentVault(), newParentVaultAddr, "Incorrect parent vault");
        assertEq(MorphoAdapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(factory.adapter(newParentVaultAddr), newAdapter, "Adapter not tracked correctly");
        assertTrue(factory.isAdapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit MorphoAdapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);

        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 amount) public {
        amount = _boundAmount(amount);

        ERC20Mock token = new ERC20Mock();

        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        deal(address(token), address(adapter), amount);
        assertEq(token.balanceOf(address(adapter)), amount, "Adapter did not receive tokens");

        vm.expectEmit();
        emit MorphoAdapter.Skim(address(token), amount);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), amount, "Recipient did not receive tokens");

        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }

    function testRealiseLossNotAuthorizedReverts() public {
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.realiseLoss(abi.encode(marketParams));
    }

    function testLossRealizationInitiallyZero() public {
        uint256 initialLoss = adapter.realisableLoss(marketId);
        assertEq(initialLoss, 0, "Initial realizable loss should be zero");
    }

    function testLossRealization(uint256 initialAmount, uint256 lossAmount) public {
        initialAmount = _boundAmount(initialAmount);
        lossAmount = bound(lossAmount, 1, initialAmount);

        // Setup: deposit assets
        deal(address(loanToken), address(adapter), initialAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), initialAmount);
        assertEq(adapter.assetsInMarket(marketId), initialAmount, "Initial assetsInMarket incorrect");

        // Loss detection during allocate
        _overrideMarketTotalSupplyAssets(initialAmount - lossAmount);
        uint256 snapshot = vm.snapshot();
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), 0);
        assertEq(adapter.realisableLoss(marketId), lossAmount, "Loss should have been tracked in allocateIn");
        vm.revertTo(snapshot);
        vm.prank(address(parentVault));
        adapter.allocateOut(abi.encode(marketParams), 0);
        assertEq(adapter.realisableLoss(marketId), lossAmount, "Loss should have been tracked in allocateOut");

        // Realise loss
        vm.prank(address(parentVault));
        (uint256 realizedLoss, bytes32[] memory ids) = adapter.realiseLoss(abi.encode(marketParams));
        assertEq(realizedLoss, lossAmount, "Realized loss should match expected loss");
        assertEq(adapter.realisableLoss(marketId), 0, "Realizable loss should be reset to zero");
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(
            ids[0],
            keccak256(
                abi.encode(
                    "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
                )
            ),
            "Incorrect id returned"
        );

        // Can't realise loss twice
        vm.prank(address(parentVault));
        (uint256 secondRealizedLoss, bytes32[] memory secondIds) = adapter.realiseLoss(abi.encode(marketParams));
        assertEq(secondRealizedLoss, 0, "Second realized loss should be zero");
        assertEq(secondIds.length, 1, "Unexpected number of ids returned");
        assertEq(
            secondIds[0],
            keccak256(
                abi.encode(
                    "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
                )
            ),
            "Incorrect id returned"
        );
    }

    function testCumulativeLossRealization(
        uint256 initialAmount,
        uint256 firstLoss,
        uint256 secondLoss,
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        initialAmount = _boundAmount(initialAmount);
        firstLoss = bound(firstLoss, 0, initialAmount / 2); // no too big otherwise next deposits' shares overflow
        secondLoss = bound(secondLoss, 0, (initialAmount - firstLoss) / 2);
        depositAmount = _boundAmount(depositAmount);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Setup
        deal(address(loanToken), address(adapter), initialAmount + depositAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), initialAmount);

        // First loss
        _overrideMarketTotalSupplyAssets(initialAmount - firstLoss);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), 0);
        assertEq(adapter.realisableLoss(marketId), firstLoss, "First loss should be tracked");

        // Second loss
        _overrideMarketTotalSupplyAssets(initialAmount - firstLoss - secondLoss);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), 0);
        assertEq(adapter.realisableLoss(marketId), firstLoss + secondLoss, "Cumulative loss should be tracked");

        // Depositing doesn't change the loss tracking
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(marketParams), depositAmount);
        assertEq(adapter.realisableLoss(marketId), firstLoss + secondLoss, "Loss should not change after deposit");

        // Withdrawing doesn't change the loss tracking
        vm.prank(address(parentVault));
        adapter.allocateOut(abi.encode(marketParams), withdrawAmount);
        assertEq(adapter.realisableLoss(marketId), firstLoss + secondLoss, "Loss should not change after withdrawal");

        // Realize loss
        vm.prank(address(parentVault));
        (uint256 realizedLoss, bytes32[] memory ids) = adapter.realiseLoss(abi.encode(marketParams));
        assertEq(realizedLoss, firstLoss + secondLoss, "Should realize the full cumulative loss");
        assertEq(adapter.realisableLoss(marketId), 0, "Realizable loss should be reset to zero");
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(
            ids[0],
            keccak256(
                abi.encode(
                    "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
                )
            ),
            "Incorrect id returned"
        );
    }

    function _overrideMarketTotalSupplyAssets(uint256 newTotalSupplyAssets) internal {
        bytes32 marketSlot0 = keccak256(abi.encode(marketId, 3)); // 3 is the slot of the market mappping.
        bytes32 currentSlot0Value = vm.load(address(morpho), marketSlot0);
        uint128 currentTotalSupplyShares = uint128(uint256(currentSlot0Value) >> 128);
        bytes32 newSlot0Value = bytes32((uint256(currentTotalSupplyShares) << 128) | uint256(newTotalSupplyAssets));
        vm.store(address(morpho), marketSlot0, newSlot0Value);
    }

    function testOverwriteMarketTotalSupplyAssets(uint256 newTotalSupplyAssets) public {
        Market memory market = morpho.market(marketId);
        newTotalSupplyAssets = _boundAmount(newTotalSupplyAssets);
        _overrideMarketTotalSupplyAssets(newTotalSupplyAssets);
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
