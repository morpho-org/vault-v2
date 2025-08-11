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
import {WAD} from "../src/VaultV2.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMorphoVaultV1AdapterFactory} from "../src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MorphoVaultV1AdapterTest is Test {
    using MathLib for uint256;

    IERC20 internal asset;
    IERC20 internal rewardToken;
    VaultV2Mock internal parentVault;
    ERC4626MockExtended internal morphoVaultV1;
    IMorphoVaultV1AdapterFactory internal factory;
    IMorphoVaultV1Adapter internal adapter;
    address internal owner;
    address internal recipient;
    bytes32[] internal expectedIds;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant EXCHANGE_RATE = 42;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));
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

        (bytes32[] memory ids, int256 change) = parentVault.allocateMocked(address(adapter), hex"", assets);

        uint256 adapterShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(adapterShares, assets * EXCHANGE_RATE, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(change, int256(assets), "Incorrect change returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, initialAssets);

        deal(address(asset), address(adapter), initialAssets);
        parentVault.allocateMocked(address(adapter), hex"", initialAssets);

        uint256 beforeShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(beforeShares, initialAssets * EXCHANGE_RATE, "Precondition failed: shares not set");

        (bytes32[] memory ids, int256 change) = parentVault.deallocateMocked(address(adapter), hex"", withdrawAssets);

        assertEq(adapter.allocation(), initialAssets - withdrawAssets, "incorrect allocation");
        uint256 afterShares = morphoVaultV1.balanceOf(address(adapter));
        assertEq(afterShares, (initialAssets - withdrawAssets) * EXCHANGE_RATE, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(change, -int256(withdrawAssets), "Incorrect change returned");
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

        expectedIds[0] = keccak256(abi.encode("this", address(newAdapter)));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(IMorphoVaultV1Adapter(newAdapter).factory(), address(factory), "Incorrect factory");
        assertEq(IMorphoVaultV1Adapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(IMorphoVaultV1Adapter(newAdapter).morphoVaultV1(), address(newVault), "Incorrect morphoVaultV1 vault");
        assertEq(IMorphoVaultV1Adapter(newAdapter).adapterId(), expectedIds[0], "Incorrect adapterId");
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

        // Can't skim morphoVaultV1
        vm.expectRevert(IMorphoVaultV1Adapter.CannotSkimMorphoVaultV1Shares.selector);
        vm.prank(recipient);
        adapter.skim(address(morphoVaultV1));
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

        ERC4626MockExtended otherVault = new ERC4626MockExtended(address(asset));

        // Deposit some assets
        deal(address(asset), address(adapter), deposit * 2);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        uint256 realAssetsBefore = adapter.realAssets();

        // Donate to adapter
        address donor = makeAddr("donor");
        deal(address(asset), donor, donation);
        vm.startPrank(donor);
        asset.approve(address(otherVault), type(uint256).max);
        otherVault.deposit(donation, address(adapter));
        vm.stopPrank();

        uint256 realAssetsAfter = adapter.realAssets();

        assertEq(realAssetsAfter, realAssetsBefore, "realAssets should not change");
    }

    function testLoss(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        loss = bound(loss, 1, deposit);

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        morphoVaultV1.lose(loss);

        assertEq(adapter.realAssets(), deposit - loss, "realAssets");
    }

    function testInterest(uint256 deposit, uint256 interest) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, deposit);

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);
        asset.transfer(address(morphoVaultV1), interest);

        // approx because of the virtual shares.
        assertApproxEqAbs(adapter.realAssets() - deposit, interest, interest.mulDivUp(1, deposit + 1), "realAssets");
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
