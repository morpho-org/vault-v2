// SPDX-License-Identifier: GPL-2.0-or-later
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

    function testParentVaultAndAssetSet() public view {
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

        assertEq(adapter.assetsInMetaMorpho(), assets, "incorrect assetsInMetaMorpho");
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

        assertEq(adapter.assetsInMetaMorpho(), initialAssets - withdrawAssets, "incorrect assetsInMetaMorpho");
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

    function testLossRealization(
        uint256 initialAssets,
        uint256 lossAssets,
        uint256 realizedLoss,
        uint256 deposit,
        uint256 withdraw,
        uint256 _interest
    ) public {
        initialAssets = bound(initialAssets, 1, MAX_TEST_ASSETS);
        lossAssets = bound(lossAssets, 1, initialAssets);
        realizedLoss = bound(realizedLoss, 0, lossAssets - 1);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        withdraw = bound(withdraw, 0, initialAssets - lossAssets);
        _interest = bound(_interest, 0, initialAssets);

        // Setup.
        deal(address(asset), address(adapter), initialAssets + deposit);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", initialAssets);

        // Loss realization with allocate.
        metaMorpho.lose(lossAssets);
        uint256 snapshot = vm.snapshotState();
        vm.prank(address(parentVault));
        (bytes32[] memory ids, uint256 interest) = adapter.allocate(hex"", 0);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
        assertEq(adapter.realizableLoss(), lossAssets, "Incorrect realizableLoss");
        assertEq(adapter.assetsInMetaMorpho(), initialAssets - lossAssets, "AssetsInMetaMorpho after allocate");

        // Loss realization with deallocate.
        vm.revertToState(snapshot);
        vm.prank(address(parentVault));
        (ids, interest) = adapter.deallocate(hex"", 0);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
        assertEq(adapter.realizableLoss(), lossAssets, "Incorrect realizableLoss");
        assertEq(adapter.assetsInMetaMorpho(), initialAssets - lossAssets, "AssetsInMetaMorpho after deallocate");

        // Can't realize more.
        vm.prank(address(parentVault));
        (ids, interest) = adapter.deallocate(hex"", 0);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
        assertEq(adapter.realizableLoss(), lossAssets, "Incorrect realizableLoss");
        assertEq(adapter.assetsInMetaMorpho(), initialAssets - lossAssets, "AssetsInMetaMorpho after rerealization");

        // Deposit realizes the right loss.
        vm.revertToState(snapshot);
        vm.prank(address(parentVault));
        (ids, interest) = adapter.allocate(hex"", deposit);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
        assertEq(adapter.realizableLoss(), lossAssets, "Incorrect realizableLoss");
        assertApproxEqAbs(
            adapter.assetsInMetaMorpho(), initialAssets - lossAssets + deposit, 1, "AssetsInMetaMorpho after deposit"
        );

        // Withdraw doesn't change the loss.
        vm.revertToState(snapshot);
        vm.prank(address(parentVault));
        (ids, interest) = adapter.deallocate(hex"", withdraw);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
        assertEq(adapter.realizableLoss(), lossAssets, "Incorrect realizableLoss");
        assertApproxEqAbs(
            adapter.assetsInMetaMorpho(), initialAssets - lossAssets - withdraw, 1, "AssetsInMetaMorpho after withdraw"
        );

        // Interest cover the loss.
        vm.revertToState(snapshot);
        asset.transfer(address(metaMorpho), _interest);
        vm.prank(address(parentVault));
        (ids, interest) = adapter.allocate(hex"", 0);
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertApproxEqAbs(interest, _interest.zeroFloorSub(lossAssets), 1, "Incorrect interest returned");
        assertApproxEqAbs(adapter.realizableLoss(), lossAssets.zeroFloorSub(_interest), 1, "Incorrect realizableLoss");
        assertApproxEqAbs(
            adapter.assetsInMetaMorpho(), initialAssets - lossAssets + _interest, 1, "AssetsInMetaMorpho after interest"
        );
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
        vm.expectRevert(IMetaMorphoAdapter.WrongAsset.selector);
        new MetaMorphoAdapter(address(parentVault), address(newMetaMorpho));
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
