// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BlueAdapter, BlueAdapterFactory} from "src/adapters/BlueAdapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams} from "lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";

/// @notice Minimal stub contract used as the parent vault by the BlueAdapter in tests.
contract VaultStub {
    address public asset;
    address public owner;

    constructor(address _asset, address _owner) {
        asset = _asset;
        owner = _owner;
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
    ERC20Mock internal rewardToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMorpho internal morpho;
    address internal owner;
    address internal recipient;

    uint256 internal constant MIN_TEST_AMOUNT = 1e6;
    uint256 internal constant MAX_TEST_AMOUNT = 1e24;

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
        parentVault = new VaultStub(address(loanToken), owner);
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
        address newParentVaultAddr = address(new VaultStub(address(loanToken), owner));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(BlueAdapter).creationCode, abi.encode(newParentVaultAddr, morpho)));
        address expectedNewAdapter = address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit BlueAdapterFactory.CreateBlueAdapter(newParentVaultAddr, expectedNewAdapter);

        address newAdapter = factory.createBlueAdapter(newParentVaultAddr);

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(BlueAdapter(newAdapter).parentVault(), newParentVaultAddr, "Incorrect parent vault");
        assertEq(BlueAdapter(newAdapter).morpho(), address(morpho), "Incorrect morpho");
        assertEq(factory.adapter(newParentVaultAddr), newAdapter, "Adapter not tracked correctly");
    }
    
    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);
        
        vm.prank(caller);
        vm.expectRevert(bytes("not authorized"));
        adapter.setSkimRecipient(newRecipient);
        
        vm.prank(owner);
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
        
        adapter.skim(address(token));
        
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), amount, "Recipient did not receive tokens");
    }
    
    function testSkimRevertsForUnderlyingToken(uint256 amount) public {
        amount = _boundAmount(amount);
        
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        
        deal(address(loanToken), address(adapter), amount);
        
        vm.expectRevert(bytes("can't skim underlying"));
        adapter.skim(address(loanToken));
    }
}
