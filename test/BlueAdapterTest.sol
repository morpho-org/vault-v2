// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BlueAdapter, BlueAdapterFactory} from "src/adapters/BlueAdapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams} from "lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

/// @notice Minimal stub contract used as the parent vault by the BlueAdapter in tests.
contract VaultStub {
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }
}

contract BlueAdapterTest is Test {
    using MorphoBalancesLib for IMorpho;

    BlueAdapterFactory internal factory;
    BlueAdapter internal adapter;
    VaultStub internal parentVault;
    MarketParams internal marketParams;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMorpho internal morpho;

    uint256 internal constant MIN_TEST_AMOUNT = 1e6;
    uint256 internal constant MAX_TEST_AMOUNT = 1e24;

    function setUp() public {
        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        loanToken = new ERC20Mock();
        collateralToken = new ERC20Mock();
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
        parentVault = new VaultStub(address(loanToken));
        factory = new BlueAdapterFactory(address(morpho));
        adapter = BlueAdapter(factory.createBlueAdapter(address(parentVault)));
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
        vm.expectRevert(bytes("not authorized"));
        adapter.allocateIn(abi.encode(marketParams), amount);
    }

    function testAllocateOutNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(bytes("not authorized"));
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

    function testAllocateOutWithdrawsAssetsFromMorpho(uint256 initialAmount, uint256 withdrawRatio) public {
        initialAmount = _boundAmount(initialAmount);
        withdrawRatio = bound(withdrawRatio, 1, 100);
        
        uint256 withdrawAmount = (initialAmount * withdrawRatio) / 100;

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

    function testFactoryCreateBlueAdapter() public {        
        address newParentVault = address(new VaultStub(address(loanToken)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(BlueAdapter).creationCode, abi.encode(newParentVault, morpho)));
        address expectedNewAdapter = address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit BlueAdapterFactory.CreateBlueAdapter(address(newParentVault), expectedNewAdapter);
        
        address newAdapter = factory.createBlueAdapter(address(newParentVault));
        
        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(BlueAdapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(BlueAdapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(factory.adapter(address(newParentVault)), newAdapter, "Adapter not tracked correctly");
    }
}
