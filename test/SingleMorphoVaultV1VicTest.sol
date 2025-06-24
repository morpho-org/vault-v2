// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import {SingleMorphoVaultV1Vic} from "../src/vic/SingleMorphoVaultV1Vic.sol";
import {SingleMorphoVaultV1VicFactory} from "../src/vic/SingleMorphoVaultV1VicFactory.sol";
import {ISingleMorphoVaultV1VicFactory} from "../src/vic/interfaces/ISingleMorphoVaultV1VicFactory.sol";
import {IMorphoVaultV1Adapter} from "../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IERC4626} from "../src/interfaces/IERC4626.sol";

uint256 constant MAX_TEST_ASSETS = 1e36;

contract MockMorphoVaultV1Adapter {
    address public immutable morphoVaultV1;

    constructor(address _morphoVaultV1) {
        morphoVaultV1 = _morphoVaultV1;
    }
}

contract SingleMorphoVaultV1VicTest is Test {
    ERC20Mock internal asset;
    ERC4626Mock internal morphoVaultV1;
    MockMorphoVaultV1Adapter internal adapter;
    SingleMorphoVaultV1Vic internal vic;
    SingleMorphoVaultV1VicFactory internal factory;
    address internal parentVault;

    function setUp() public {
        asset = new ERC20Mock();
        morphoVaultV1 = new ERC4626Mock(address(asset));
        adapter = new MockMorphoVaultV1Adapter(address(morphoVaultV1));
        parentVault = makeAddr("parentVault");
        vic = new SingleMorphoVaultV1Vic(parentVault, address(adapter));
        factory = new SingleMorphoVaultV1VicFactory();

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(morphoVaultV1), type(uint256).max);
    }

    function testConstructor() public {
        SingleMorphoVaultV1Vic newVic = new SingleMorphoVaultV1Vic(parentVault, address(adapter));
        assertEq(newVic.morphoVaultV1Adapter(), address(adapter), "morphoVaultV1Adapter not set correctly");
        assertEq(newVic.morphoVaultV1(), address(morphoVaultV1), "morphoVaultV1 not set correctly");
    }

    function testInterestPerSecondVaultOnly(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        assertEq(vic.interestPerSecond(deposit, elapsed), realVaultInterest / elapsed, "interest per second");
    }

    function testInterestPerSecondIdleOnly(uint256 deposit, uint256 idleInterest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        idleInterest = bound(idleInterest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(parentVault), idleInterest);

        assertEq(vic.interestPerSecond(deposit, elapsed), idleInterest / elapsed, "interest per second");
    }

    function testInterestPerSecondVaultAndIdle(
        uint256 deposit,
        uint256 vaultInterest,
        uint256 idleInterest,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        vaultInterest = bound(vaultInterest, 1, MAX_TEST_ASSETS);
        idleInterest = bound(idleInterest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), vaultInterest);
        asset.transfer(address(parentVault), idleInterest);
        uint256 realVaultInterest = vaultInterest * deposit / (deposit + 1); // account for the virtual share.

        assertEq(
            vic.interestPerSecond(deposit, elapsed), (realVaultInterest + idleInterest) / elapsed, "interest per second"
        );
    }

    function testInterestPerSecondZero(uint256 deposit, uint256 loss, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        loss = bound(loss, 1, deposit);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        vm.prank(address(morphoVaultV1));
        asset.transfer(address(0xdead), loss);

        assertEq(vic.interestPerSecond(deposit, elapsed), 0, "interest per second");
    }

    function testCreateSingleMorphoVaultV1Vic() public {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(SingleMorphoVaultV1Vic).creationCode, abi.encode(parentVault, address(adapter)))
        );
        address expectedVic = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(factory), bytes32(0), initCodeHash))))
        );

        vm.mockCall(
            address(adapter), abi.encodeCall(IMorphoVaultV1Adapter.morphoVaultV1, ()), abi.encode(morphoVaultV1)
        );
        vm.expectEmit();
        emit ISingleMorphoVaultV1VicFactory.CreateSingleMorphoVaultV1Vic(expectedVic, parentVault, address(adapter));
        address newVic = factory.createSingleMorphoVaultV1Vic(parentVault, address(adapter));

        assertEq(newVic, expectedVic, "createSingleMorphoVaultV1Vic returned wrong address");
        assertTrue(factory.isSingleMorphoVaultV1Vic(newVic), "Factory did not mark vic as valid");
        assertEq(factory.singleMorphoVaultV1Vic(address(parentVault), address(adapter)), newVic, "Mapping not updated");
        assertEq(SingleMorphoVaultV1Vic(newVic).morphoVaultV1Adapter(), address(adapter), "Vic initialized incorrectly");
        assertEq(SingleMorphoVaultV1Vic(newVic).morphoVaultV1(), address(morphoVaultV1), "Vic initialized incorrectly");
        assertEq(SingleMorphoVaultV1Vic(newVic).parentVault(), parentVault, "Vic initialized incorrectly");
    }
}
