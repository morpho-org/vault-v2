// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import {IERC4626} from "../src/interfaces/IERC4626.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IMorphoVaultV1Adapter} from "../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {MorphoVaultV1Adapter} from "../src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoVaultV1AdapterFactory} from "../src/adapters/MorphoVaultV1AdapterFactory.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMorphoVaultV1AdapterFactory} from "../src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MorphoVaultV1AdapterTest is Test {
    using MathLib for uint256;

    ERC20Mock internal asset;
    ERC20Mock internal rewardToken;
    VaultV2Mock internal parentVault;
    ERC4626MockExtended internal morphoVaultV1;
    MorphoVaultV1AdapterFactory internal factory;
    MorphoVaultV1Adapter internal adapter;
    address internal owner;
    address internal recipient;
    bytes32[] internal expectedIds;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant EXCHANGE_RATE = 42;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = new ERC20Mock(18);
        rewardToken = new ERC20Mock(18);
        morphoVaultV1 = new ERC4626MockExtended(address(asset));
        parentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));

        factory = new MorphoVaultV1AdapterFactory();
        adapter = MorphoVaultV1Adapter(factory.createMorphoVaultV1Adapter(address(parentVault), address(morphoVaultV1)));

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(morphoVaultV1), type(uint256).max);

        // Increase the exchange rate to make so 1 asset is worth EXCHANGE_RATE shares.
        deal(address(morphoVaultV1), address(0), EXCHANGE_RATE - 1, true);
        assertEq(morphoVaultV1.convertToShares(1), EXCHANGE_RATE, "exchange rate not set correctly");

        expectedIds = new bytes32[](1);
        expectedIds[0] = keccak256(abi.encode("this", address(adapter)));
    }

    function testFactoryAndParentVaultAndAssetSet() public view {
        assertEq(adapter.factory(), address(factory), "Incorrect factory set");
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.morphoVaultV1(), address(morphoVaultV1), "Incorrect morphoVaultV1 vault set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IMorphoVaultV1Adapter.NotAuthorized.selector);
        adapter.allocate(hex"", assets, bytes4(0), address(0));
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IMorphoVaultV1Adapter.NotAuthorized.selector);
        adapter.deallocate(hex"", assets, bytes4(0), address(0));
    }

    function testAllocate(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        deal(address(asset), address(adapter), assets);

        (bytes32[] memory ids, uint256 interest) = parentVault.allocateMocked(address(adapter), hex"", assets);

        uint256 adapterShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(adapterShares, assets * EXCHANGE_RATE, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(interest, 0, "Incorrect interest returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, initialAssets);

        deal(address(asset), address(adapter), initialAssets);
        parentVault.allocateMocked(address(adapter), hex"", initialAssets);

        uint256 beforeShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(beforeShares, initialAssets * EXCHANGE_RATE, "Precondition failed: shares not set");

        (bytes32[] memory ids, uint256 interest) = parentVault.deallocateMocked(address(adapter), hex"", withdrawAssets);

        assertEq(adapter.allocation(), initialAssets - withdrawAssets, "incorrect allocation");
        uint256 afterShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(afterShares, (initialAssets - withdrawAssets) * EXCHANGE_RATE, "Share balance not decreased correctly");

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
                type(MorphoVaultV1Adapter).creationCode, abi.encode(address(newParentVault), address(newVault))
            )
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit IMorphoVaultV1AdapterFactory.CreateMorphoVaultV1Adapter(
            address(newParentVault), address(newVault), expectedNewAdapter
        );

        address newAdapter = factory.createMorphoVaultV1Adapter(address(newParentVault), address(newVault));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(MorphoVaultV1Adapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(MorphoVaultV1Adapter(newAdapter).morphoVaultV1(), address(newVault), "Incorrect morphoVaultV1 vault");
        assertEq(
            factory.morphoVaultV1Adapter(address(newParentVault), address(newVault)),
            newAdapter,
            "Adapter not tracked correctly"
        );
        assertTrue(factory.isMorphoVaultV1Adapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        // Access control
        vm.prank(caller);
        vm.expectRevert(IMorphoVaultV1Adapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit IMorphoVaultV1Adapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        ERC20Mock token = new ERC20Mock(18);

        // Setup
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        // Normal path
        vm.expectEmit();
        emit IMorphoVaultV1Adapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        // Access control
        vm.expectRevert(IMorphoVaultV1Adapter.NotAuthorized.selector);
        adapter.skim(address(token));

        // Cant skim morphoVaultV1
        vm.expectRevert(IMorphoVaultV1Adapter.CannotSkimMorphoVaultV1Shares.selector);
        vm.prank(recipient);
        adapter.skim(address(morphoVaultV1));
    }

    function testLossRealizationImpossible(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        asset.transfer(address(morphoVaultV1), 2);

        // Realize loss.
        vm.prank(address(parentVault));
        vm.expectRevert(stdError.arithmeticError);
        adapter.realizeLoss(hex"", bytes4(0), address(0));
    }

    function testLossRealizationNotMocked() public {
        vm.prank(address(parentVault));
        adapter.realizeLoss(hex"", bytes4(0), address(0));
    }

    function testLossRealizationZero(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), hex"");
        assertEq(ids, expectedIds, "ids");
        assertEq(loss, 0, "loss");
    }

    function testLossRealization(uint256 deposit, uint256 _loss) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        _loss = bound(_loss, 1, deposit);

        // Setup.
        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        morphoVaultV1.lose(_loss);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), hex"");
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
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        morphoVaultV1.lose(_loss);

        // Allocate.
        parentVault.allocateMocked(address(adapter), hex"", deposit2);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), hex"");
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
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        morphoVaultV1.lose(_loss);

        // Deallocate.
        withdraw = bound(withdraw, 1, morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(adapter))));
        parentVault.deallocateMocked(address(adapter), hex"", withdraw);

        // Realize loss.
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), hex"");
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
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        uint256 expectedSupplyBefore = morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(adapter)));
        morphoVaultV1.lose(_loss);

        // Realize loss.
        asset.transfer(address(morphoVaultV1), interest);
        uint256 expectedSupplyAfter = morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(adapter)));
        vm.prank(address(parentVault));
        if (expectedSupplyAfter > expectedSupplyBefore) vm.expectRevert(stdError.arithmeticError);
        (bytes32[] memory ids, uint256 loss) = parentVault.realizeLossMocked(address(adapter), hex"");
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

        vm.expectRevert(IMorphoVaultV1Adapter.InvalidData.selector);
        adapter.allocate(data, 0, bytes4(0), address(0));

        vm.expectRevert(IMorphoVaultV1Adapter.InvalidData.selector);
        adapter.deallocate(data, 0, bytes4(0), address(0));

        vm.expectRevert(IMorphoVaultV1Adapter.InvalidData.selector);
        adapter.realizeLoss(data, bytes4(0), address(0));
    }

    function testDifferentAssetReverts(address randomAsset) public {
        vm.assume(randomAsset != parentVault.asset());
        ERC4626MockExtended newMorphoVaultV1 = new ERC4626MockExtended(randomAsset);
        vm.expectRevert(IMorphoVaultV1Adapter.AssetMismatch.selector);
        new MorphoVaultV1Adapter(address(parentVault), address(newMorphoVaultV1));
    }

    function testDonationResistance(uint256 deposit, uint256 donation) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        donation = bound(donation, 1, MAX_TEST_ASSETS);

        // Deposit some assets
        deal(address(asset), address(adapter), deposit * 2);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        uint256 adapterShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(adapter.shares(), adapterShares, "shares not recorded");

        // Donate to adapter
        address donor = makeAddr("donor");
        deal(address(asset), donor, donation);
        vm.startPrank(donor);
        asset.approve(address(morphoVaultV1), type(uint256).max);
        morphoVaultV1.deposit(donation, address(adapter));
        vm.stopPrank();

        // Test no impact on allocation
        uint256 oldallocation = adapter.allocation();
        parentVault.allocateMocked(address(adapter), hex"", deposit);
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
