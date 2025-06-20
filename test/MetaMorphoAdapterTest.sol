// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import {IERC4626} from "../src/interfaces/IERC4626.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IMetaMorphoAdapter} from "../src/adapters/interfaces/IMetaMorphoAdapter.sol";
import {MetaMorphoAdapter} from "../src/adapters/MetaMorphoAdapter.sol";
import {MetaMorphoAdapterFactory} from "../src/adapters/MetaMorphoAdapterFactory.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMetaMorphoAdapterFactory} from "../src/adapters/interfaces/IMetaMorphoAdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MetaMorphoAdapterTest is Test {
    using MathLib for uint256;

    ERC20Mock internal asset;
    ERC20Mock internal rewardToken;
    VaultV2Mock internal parentVault;
    ERC4626MockExtended internal metaMorpho;
    MetaMorphoAdapterFactory internal factory;
    MetaMorphoAdapter internal adapter;
    address internal owner;
    address internal recipient;
    bytes32[] internal expectedIds;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = new ERC20Mock();
        rewardToken = new ERC20Mock();
        metaMorpho = new ERC4626MockExtended(address(asset));
        parentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));

        factory = new MetaMorphoAdapterFactory();
        adapter = MetaMorphoAdapter(factory.createMetaMorphoAdapter(address(parentVault), address(metaMorpho)));

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(metaMorpho), type(uint256).max);

        expectedIds = new bytes32[](1);
        expectedIds[0] = keccak256(abi.encode("adapter", address(adapter)));
    }

    function testFactoryAndParentVaultAndAssetSet() public view {
        assertEq(adapter.factory(), address(factory), "Incorrect factory set");
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.metaMorpho(), address(metaMorpho), "Incorrect metaMorpho vault set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IMetaMorphoAdapter.NotAuthorized.selector);
        adapter.allocate(hex"", assets);
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IMetaMorphoAdapter.NotAuthorized.selector);
        adapter.deallocate(hex"", assets);
    }

    function testAllocate(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        deal(address(asset), address(adapter), assets);

        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest) = adapter.allocate(hex"", assets);

        assertEq(adapter.allocation(), assets, "incorrect allocation");
        uint256 adapterShares = metaMorpho.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(adapterShares, assets, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, initialAssets);

        deal(address(asset), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", initialAssets);

        uint256 beforeShares = metaMorpho.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(beforeShares, initialAssets, "Precondition failed: shares not set");

        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest) = adapter.deallocate(hex"", withdrawAssets);

        assertEq(adapter.allocation(), initialAssets - withdrawAssets, "incorrect allocation");
        uint256 afterShares = metaMorpho.balanceOf(address(adapter));
        assertEq(afterShares, initialAssets - withdrawAssets, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
    }

    function testFactoryCreateAdapter() public {
        VaultV2Mock newParentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));
        ERC4626Mock newVault = new ERC4626Mock(address(asset));

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(MetaMorphoAdapter).creationCode, abi.encode(address(newParentVault), address(newVault))
            )
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit IMetaMorphoAdapterFactory.CreateMetaMorphoAdapter(
            address(newParentVault), address(newVault), expectedNewAdapter
        );

        address newAdapter = factory.createMetaMorphoAdapter(address(newParentVault), address(newVault));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MetaMorphoAdapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(MetaMorphoAdapter(newAdapter).metaMorpho(), address(newVault), "Incorrect metaMorpho vault");
        assertEq(
            factory.metaMorphoAdapter(address(newParentVault), address(newVault)),
            newAdapter,
            "Adapter not tracked correctly"
        );
        assertTrue(factory.isMetaMorphoAdapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        // Access control
        vm.prank(caller);
        vm.expectRevert(IMetaMorphoAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit IMetaMorphoAdapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        ERC20Mock token = new ERC20Mock();

        // Setup
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        // Normal path
        vm.expectEmit();
        emit IMetaMorphoAdapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        // Access control
        vm.expectRevert(IMetaMorphoAdapter.NotAuthorized.selector);
        adapter.skim(address(token));

        // Cant skim metaMorpho
        vm.expectRevert(IMetaMorphoAdapter.CannotSkimMetaMorphoShares.selector);
        vm.prank(recipient);
        adapter.skim(address(metaMorpho));
    }

    function testLossRealizationImpossible(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        asset.transfer(address(metaMorpho), 2);

        // Realize loss.
        vm.prank(address(parentVault));
        vm.expectRevert(stdError.arithmeticError);
        adapter.realizePnL(hex"");
    }

    function testLossRealizationZero(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);

        // Realize loss.
        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest, uint256 loss) = adapter.realizePnL(hex"");
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, 0, "loss");
        assertEq(adapter.allocation(), deposit, "allocation");
    }

    function testLossRealization(uint256 deposit, uint256 _loss) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        _loss = bound(_loss, 1, deposit);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        metaMorpho.lose(_loss);

        // Realize loss.
        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest, uint256 loss) = adapter.realizePnL(hex"");
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(), deposit - _loss, "allocation");
    }

    function testLossRealizationAfterAllocate(uint256 deposit, uint256 _loss, uint256 deposit2) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        _loss = bound(_loss, 1, deposit);
        deposit2 = bound(deposit2, 0, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit + deposit2);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        metaMorpho.lose(_loss);

        // Allocate.
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit2);

        // Realize loss.
        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest, uint256 loss) = adapter.realizePnL(hex"");
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(), deposit - _loss + deposit2, "allocation");
    }

    function testLossRealizationAfterDeallocate(uint256 deposit, uint256 _loss, uint256 withdraw) public {
        deposit = bound(deposit, 2, MAX_TEST_ASSETS);
        _loss = bound(_loss, 1, deposit - 1);
        withdraw = bound(withdraw, 0, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit + withdraw);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        metaMorpho.lose(_loss);

        // Deallocate.
        withdraw = bound(withdraw, 1, metaMorpho.previewRedeem(metaMorpho.balanceOf(address(adapter))));
        vm.prank(address(parentVault));
        adapter.deallocate(hex"", withdraw);

        // Realize loss.
        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest, uint256 loss) = adapter.realizePnL(hex"");
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, _loss, "loss");
        assertEq(adapter.allocation(), deposit - _loss - withdraw, "allocation");
    }

    function testLossRealizationAfterInterest(uint256 deposit, uint256 _loss, uint256 interest) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        _loss = bound(_loss, 1, deposit);
        interest = bound(interest, 0, deposit);

        // Setup.
        deal(address(asset), address(adapter), deposit + interest);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        uint256 expectedSupplyBefore = metaMorpho.previewRedeem(metaMorpho.balanceOf(address(adapter)));
        metaMorpho.lose(_loss);

        // Realize loss.
        asset.transfer(address(metaMorpho), interest);
        uint256 expectedSupplyAfter = metaMorpho.previewRedeem(metaMorpho.balanceOf(address(adapter)));
        vm.prank(address(parentVault));
        if (expectedSupplyAfter > expectedSupplyBefore) vm.expectRevert(stdError.arithmeticError);
        (bytes32[] memory ids, uint256 interest2, uint256 loss) = adapter.realizePnL(hex"");
        if (_loss >= interest) {
            assertEq(ids, expectedIds, "ids");
            assertEq(loss, _loss - interest, "loss");
            assertApproxEqAbs(adapter.allocation(), deposit - _loss + interest, 1, "allocation");
        }
    }

    function testIds() public view {
        assertEq(adapter.ids(), expectedIds);
    }

    function testInvalidData(bytes memory data) public {
        vm.assume(data.length > 0);

        vm.expectRevert(IMetaMorphoAdapter.InvalidData.selector);
        adapter.allocate(data, 0);

        vm.expectRevert(IMetaMorphoAdapter.InvalidData.selector);
        adapter.deallocate(data, 0);
    }

    function testDifferentAssetReverts(address randomAsset) public {
        vm.assume(randomAsset != parentVault.asset());
        ERC4626MockExtended newMetaMorpho = new ERC4626MockExtended(randomAsset);
        vm.expectRevert(IMetaMorphoAdapter.AssetMismatch.selector);
        new MetaMorphoAdapter(address(parentVault), address(newMetaMorpho));
    }

    function testDonationResistance(uint256 deposit, uint256 donation) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        donation = bound(donation, 1, MAX_TEST_ASSETS);

        // Deposit some assets
        deal(address(asset), address(adapter), deposit * 2);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);

        uint256 adapterShares = metaMorpho.balanceOf(address(adapter));
        assertEq(adapter.shares(), adapterShares, "shares not recorded");

        // Donate to adapter
        address donor = makeAddr("donor");
        deal(address(asset), donor, donation);
        vm.startPrank(donor);
        asset.approve(address(metaMorpho), type(uint256).max);
        metaMorpho.deposit(donation, address(adapter));
        vm.stopPrank();

        // Test no impact on allocation
        uint256 oldallocation = adapter.allocation();
        vm.prank(address(parentVault));
        adapter.allocate(hex"", deposit);
        assertEq(adapter.allocation(), oldallocation + deposit, "assets have changed");
    }
}

contract ERC4626MockExtended is ERC4626Mock {
    constructor(address _asset) ERC4626Mock(_asset) {}

    function lose(uint256 assets) public {
        IERC20(asset()).transfer(address(0xdead), assets);
    }
}

function zeroFloorSub(uint256 a, uint256 b) pure returns (uint256) {
    if (a < b) return 0;
    return a - b;
}
