// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {MorphoAdapter} from "src/adapters/MorphoAdapter.sol";
import {MorphoAdapterFactory} from "src/adapters/MorphoAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IrmMock} from "lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams} from "lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";

contract MorphoAdapterTest is Test {
    using MorphoBalancesLib for IMorpho;

    MorphoAdapterFactory internal factory;
    MorphoAdapter internal adapter;
    VaultV2Mock internal parentVault;
    MarketParams internal marketParams;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    ERC20Mock internal rewardToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMorpho internal morpho;
    address internal owner;
    address internal recipient;

    uint256 internal constant MIN_TEST_ASSETS = 1;
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
        parentVault = new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0));
        factory = new MorphoAdapterFactory(address(morpho));
        adapter = MorphoAdapter(factory.createMorphoAdapter(address(parentVault)));
    }

    function _boundsAssets(uint256 assets) internal pure returns (uint256) {
        return bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
    }

    function testParentVaultAndMorphoSet() public view {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.morpho(), address(morpho), "Incorrect morpho set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundsAssets(assets);
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.allocate(abi.encode(marketParams), assets);
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = _boundsAssets(assets);
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.deallocate(abi.encode(marketParams), assets);
    }

    function testAllocateSuppliesAssetsToMorpho(uint256 assets) public {
        assets = _boundsAssets(assets);
        deal(address(loanToken), address(adapter), assets);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocate(abi.encode(marketParams), assets);

        uint256 supplied = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(supplied, assets, "Incorrect supplied assets in Morpho");

        bytes32 expectedId0 = keccak256(abi.encode("adapter", address(adapter)));
        bytes32 expectedId1 = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        bytes32 expectedId2 = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        assertEq(ids.length, 3, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId0, "Incorrect id #0 returned");
        assertEq(ids[1], expectedId1, "Incorrect id #1 returned");
        assertEq(ids[2], expectedId2, "Incorrect id #2 returned");
    }

    function testAllocateWithdrawsAssetsFromMorpho(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = _boundsAssets(initialAssets);
        withdrawAssets = bound(withdrawAssets, 1, initialAssets);

        deal(address(loanToken), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(abi.encode(marketParams), initialAssets);

        uint256 beforeSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(beforeSupply, initialAssets, "Precondition failed: supply not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.deallocate(abi.encode(marketParams), withdrawAssets);

        uint256 afterSupply = morpho.expectedSupplyAssets(marketParams, address(adapter));
        assertEq(afterSupply, initialAssets - withdrawAssets, "Supply not decreased correctly");

        uint256 adapterBalance = loanToken.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");

        bytes32 expectedId0 = keccak256(abi.encode("adapter", address(adapter)));
        bytes32 expectedId1 = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        bytes32 expectedId2 = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        assertEq(ids.length, 3, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId0, "Incorrect id #0 returned");
        assertEq(ids[1], expectedId1, "Incorrect id #1 returned");
        assertEq(ids[2], expectedId2, "Incorrect id #2 returned");
    }

    function testFactoryCreateMorphoAdapter() public {
        address newParentVaultAddr =
            address(new VaultV2Mock(address(loanToken), owner, address(0), address(0), address(0)));

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(MorphoAdapter).creationCode, abi.encode(newParentVaultAddr, morpho)));
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit MorphoAdapterFactory.CreateMorphoAdapter(expectedNewAdapter, newParentVaultAddr);

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
        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit MorphoAdapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);

        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = _boundsAssets(assets);

        ERC20Mock token = new ERC20Mock();

        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        vm.expectEmit();
        emit MorphoAdapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        vm.expectRevert(MorphoAdapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }
}
