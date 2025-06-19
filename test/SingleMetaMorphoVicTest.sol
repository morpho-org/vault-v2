// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import {SingleMetaMorphoVic} from "../src/vic/SingleMetaMorphoVic.sol";
import {SingleMetaMorphoVicFactory} from "../src/vic/SingleMetaMorphoVicFactory.sol";
import {ISingleMetaMorphoVicFactory} from "../src/vic/interfaces/ISingleMetaMorphoVicFactory.sol";
import {IMetaMorphoAdapter} from "../src/adapters/interfaces/IMetaMorphoAdapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IERC4626} from "../src/interfaces/IERC4626.sol";

uint256 constant MAX_TEST_ASSETS = 1e36;

contract MockMetaMorphoAdapter is IMetaMorphoAdapter {
    address public immutable override metaMorpho;

    constructor(address _metaMorpho) {
        metaMorpho = _metaMorpho;
    }

    function factory() external pure override returns (address) {
        return address(0);
    }

    function parentVault() external pure override returns (address) {
        return address(0);
    }

    function skimRecipient() external pure override returns (address) {
        return address(0);
    }

    function setSkimRecipient(address) external override {}
    function skim(address) external override {}

    function allocate(bytes memory, uint256) external pure override returns (bytes32[] memory ids, uint256 loss) {
        ids = new bytes32[](0);
        loss = 0;
    }

    function deallocate(bytes memory, uint256) external pure override returns (bytes32[] memory ids, uint256 loss) {
        ids = new bytes32[](0);
        loss = 0;
    }
}

contract SingleMetaMorphoVicTest is Test {
    ERC20Mock internal asset;
    ERC4626Mock internal metaMorpho;
    MockMetaMorphoAdapter internal adapter;
    SingleMetaMorphoVic internal vic;
    SingleMetaMorphoVicFactory internal factory;

    function setUp() public {
        asset = new ERC20Mock();
        metaMorpho = new ERC4626Mock(address(asset));
        adapter = new MockMetaMorphoAdapter(address(metaMorpho));
        vic = new SingleMetaMorphoVic(address(adapter));
        factory = new SingleMetaMorphoVicFactory();

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(metaMorpho), type(uint256).max);
    }

    function testConstructor(address randomAdapter) public {
        vm.assume(randomAdapter != address(0));
        SingleMetaMorphoVic newVic = new SingleMetaMorphoVic(randomAdapter);
        assertEq(newVic.metaMorphoAdapter(), randomAdapter, "metaMorphoAdapter not set correctly");
    }

    function testInterestPerSecond(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        metaMorpho.deposit(deposit, address(adapter));
        asset.transfer(address(metaMorpho), interest);
        uint256 finalInterest = metaMorpho.previewRedeem(metaMorpho.balanceOf(address(adapter))) - deposit;

        assertEq(vic.interestPerSecond(deposit, elapsed), finalInterest / elapsed, "interest per second");
    }

    function testInterestPerSecondZero(uint256 deposit, uint256 loss, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        loss = bound(loss, 1, deposit);
        elapsed = bound(elapsed, 1, 2 ** 63);

        metaMorpho.deposit(deposit, address(adapter));
        vm.prank(address(metaMorpho));
        asset.transfer(address(0xdead), loss);

        assertEq(vic.interestPerSecond(deposit, elapsed), 0, "interest per second");
    }

    function testCreateSingleMetaMorphoVic(address metaMorphoAdapter) public {
        vm.assume(metaMorphoAdapter != address(0));

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(SingleMetaMorphoVic).creationCode, abi.encode(metaMorphoAdapter)));
        address expectedVic = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(factory), bytes32(0), initCodeHash))))
        );

        vm.expectEmit();
        emit ISingleMetaMorphoVicFactory.CreateSingleMetaMorphoVic(expectedVic, metaMorphoAdapter);
        address newVic = factory.createSingleMetaMorphoVic(metaMorphoAdapter);

        assertEq(newVic, expectedVic, "createSingleMetaMorphoVic returned wrong address");
        assertTrue(factory.isSingleMetaMorphoVic(newVic), "Factory did not mark vic as valid");
        assertEq(factory.singleMetaMorphoVic(metaMorphoAdapter), newVic, "Mapping not updated");
        assertEq(SingleMetaMorphoVic(newVic).metaMorphoAdapter(), metaMorphoAdapter, "Vic initialized incorrectly");
    }
}
