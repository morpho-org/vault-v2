// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

import {SingleMorphoVaultV1Vic} from "../src/vic/SingleMorphoVaultV1Vic.sol";
import {SingleMorphoVaultV1VicFactory} from "../src/vic/SingleMorphoVaultV1VicFactory.sol";
import {ISingleMorphoVaultV1Vic} from "../src/vic/interfaces/ISingleMorphoVaultV1Vic.sol";
import {ISingleMorphoVaultV1VicFactory} from "../src/vic/interfaces/ISingleMorphoVaultV1VicFactory.sol";
import {IMorphoVaultV1Adapter} from "../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IERC4626} from "../src/interfaces/IERC4626.sol";

uint256 constant MAX_TEST_ASSETS = 1e36;

contract MockMorphoVaultV1Adapter {
    address public immutable morphoVaultV1;
    address public immutable parentVault;

    constructor(address _parentVault, address _morphoVaultV1) {
        morphoVaultV1 = _morphoVaultV1;
        parentVault = _parentVault;
    }

    function shares() external view returns (uint256) {
        return IERC4626(morphoVaultV1).balanceOf(address(this));
    }
}

contract SingleMorphoVaultV1VicTest is Test {
    using MathLib for uint256;

    ERC20Mock internal asset;
    ERC4626Mock internal morphoVaultV1;
    MockMorphoVaultV1Adapter internal adapter;
    ISingleMorphoVaultV1Vic internal vic;
    ISingleMorphoVaultV1VicFactory internal factory;
    address internal parentVault;

    function setUp() public {
        asset = new ERC20Mock(18);
        morphoVaultV1 = new ERC4626Mock(address(asset));
        parentVault = makeAddr("parentVault");
        adapter = new MockMorphoVaultV1Adapter(parentVault, address(morphoVaultV1));
        vic = ISingleMorphoVaultV1Vic(address(new SingleMorphoVaultV1Vic(address(adapter))));
        factory = ISingleMorphoVaultV1VicFactory(address(new SingleMorphoVaultV1VicFactory()));

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(morphoVaultV1), type(uint256).max);
    }

    function testConstructor() public {
        SingleMorphoVaultV1Vic newVic = new SingleMorphoVaultV1Vic(address(adapter));
        assertEq(newVic.morphoVaultV1Adapter(), address(adapter), "morphoVaultV1Adapter not set correctly");
        assertEq(newVic.morphoVaultV1(), address(morphoVaultV1), "morphoVaultV1 not set correctly");
    }

    function testInterestPerSecondVaultOnlyWithSmallInterest(uint256 deposit, uint256 interest, uint256 elapsed)
        public
    {
        deposit = bound(deposit, 1e18, MAX_TEST_ASSETS);
        // At most 1% APR
        interest = bound(interest, 1, deposit / (100 * uint256(365 days)));
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        uint256 expectedInterestPerSecond = realVaultInterest / elapsed;
        assertEq(vic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
    }

    function testInterestPerSecondVaultOnly(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        uint256 expectedInterestPerSecond = boundInterestPerSecond(realVaultInterest, deposit, elapsed);
        assertEq(vic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
    }

    function testInterestPerSecondVaultOnlyWithBigInterest(uint256 deposit, uint256 interest, uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);
        deposit = bound(deposit, 1e18, MAX_TEST_ASSETS / (elapsed * 1000));
        // At least 1000% APR
        interest = bound(interest, 1000 * deposit * elapsed / uint256(365 days), MAX_TEST_ASSETS);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        assertLt(vic.interestPerSecond(deposit, elapsed), realVaultInterest / elapsed, "interest per second");
    }

    function testInterestPerSecondIdleOnly(uint256 deposit, uint256 idleInterest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        idleInterest = bound(idleInterest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        morphoVaultV1.deposit(deposit, address(adapter));
        asset.transfer(address(parentVault), idleInterest);

        uint256 expectedInterestPerSecond = boundInterestPerSecond(idleInterest, deposit, elapsed);
        assertEq(vic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
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

        uint256 expectedInterestPerSecond = boundInterestPerSecond(realVaultInterest + idleInterest, deposit, elapsed);
        assertEq(vic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
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
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(SingleMorphoVaultV1Vic).creationCode, abi.encode(address(adapter))));
        address expectedVic = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(factory), bytes32(0), initCodeHash))))
        );

        vm.mockCall(
            address(adapter), abi.encodeCall(IMorphoVaultV1Adapter.morphoVaultV1, ()), abi.encode(morphoVaultV1)
        );
        vm.expectEmit();
        emit ISingleMorphoVaultV1VicFactory.CreateSingleMorphoVaultV1Vic(expectedVic, address(adapter));
        address newVic = factory.createSingleMorphoVaultV1Vic(address(adapter));

        assertEq(newVic, expectedVic, "createSingleMorphoVaultV1Vic returned wrong address");
        assertTrue(factory.isSingleMorphoVaultV1Vic(newVic), "Factory did not mark vic as valid");
        assertEq(factory.singleMorphoVaultV1Vic(address(adapter)), newVic, "Mapping not updated");
        assertEq(SingleMorphoVaultV1Vic(newVic).morphoVaultV1Adapter(), address(adapter), "Vic initialized incorrectly");
        assertEq(SingleMorphoVaultV1Vic(newVic).morphoVaultV1(), address(morphoVaultV1), "Vic initialized incorrectly");
        assertEq(SingleMorphoVaultV1Vic(newVic).parentVault(), parentVault, "Vic initialized incorrectly");
    }

    function boundInterestPerSecond(uint256 interest, uint256 totalAssets, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        uint256 tentativeInterestPerSecond = interest / elapsed;
        uint256 maxInterestPerSecond = totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD);
        return tentativeInterestPerSecond <= maxInterestPerSecond ? tentativeInterestPerSecond : maxInterestPerSecond;
    }
}
