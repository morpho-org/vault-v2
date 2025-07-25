// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {OnchainVic} from "../src/vic/OnchainVic.sol";
import {OnchainVicFactory} from "../src/vic/OnchainVicFactory.sol";
import {IOnchainVicFactory} from "../src/vic/interfaces/IOnchainVicFactory.sol";

import {VaultV2} from "../src/VaultV2.sol";

import {IMorphoVaultV1Adapter} from "../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {MorphoVaultV1Adapter} from "../src/adapters/MorphoVaultV1Adapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IERC4626} from "../src/interfaces/IERC4626.sol";

uint256 constant MAX_TEST_ASSETS = 1e36;

contract OnchainVicTest is BaseTest {
    using MathLib for uint256;

    ERC20Mock internal asset;
    ERC4626Mock internal morphoVaultV1;
    MorphoVaultV1Adapter internal adapter;
    OnchainVic internal onchainVic;
    OnchainVicFactory internal factory;

    function setUp() public override {
        super.setUp();

        asset = ERC20Mock(address(underlyingToken));
        morphoVaultV1 = new ERC4626Mock(address(underlyingToken));
        adapter = new MorphoVaultV1Adapter(address(vault), address(morphoVaultV1));
        onchainVic = new OnchainVic(address(vault));
        factory = new OnchainVicFactory();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        vm.startPrank(curator);
        vault.submit(
            abi.encodeCall(IVaultV2.increaseAbsoluteCap, (abi.encode("this", address(adapter)), type(uint128).max))
        );
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (abi.encode("this", address(adapter)), WAD)));
        vm.stopPrank();
        vault.increaseAbsoluteCap(abi.encode("this", address(adapter)), type(uint128).max);
        vault.increaseRelativeCap(abi.encode("this", address(adapter)), WAD);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(morphoVaultV1), type(uint256).max);
    }

    function testConstructor() public {
        OnchainVic newVic = new OnchainVic(address(vault));
        assertEq(newVic.parentVault(), address(vault), "parentVault not set correctly");
        assertEq(newVic.asset(), address(asset), "asset not set correctly");
    }

    function testInterestPerSecondVaultOnlyWithSmallInterest(uint256 deposit, uint256 interest, uint256 elapsed)
        public
    {
        deposit = bound(deposit, 1e18, MAX_TEST_ASSETS);
        // At most 1% APR
        interest = bound(interest, 1, deposit / (100 * uint256(365 days)));
        elapsed = bound(elapsed, 1, 2 ** 63);

        vault.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        uint256 expectedInterestPerSecond = realVaultInterest / elapsed;
        assertEq(onchainVic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
    }

    function testInterestPerSecondVaultOnly(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        vault.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        uint256 expectedInterestPerSecond = boundInterestPerSecond(realVaultInterest, deposit, elapsed);
        assertEq(onchainVic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
    }

    function testInterestPerSecondVaultOnlyWithBigInterest(uint256 deposit, uint256 interest, uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);
        deposit = bound(deposit, 1e18, MAX_TEST_ASSETS / (elapsed * 1000));
        // At least 1000% APR
        interest = bound(interest, 1000 * deposit * elapsed / uint256(365 days), MAX_TEST_ASSETS);

        vault.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), interest);
        uint256 realVaultInterest = interest * deposit / (deposit + 1); // account for the virtual share.

        assertLt(onchainVic.interestPerSecond(deposit, elapsed), realVaultInterest / elapsed, "interest per second");
    }

    function testInterestPerSecondIdleOnly(uint256 deposit, uint256 idleInterest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        idleInterest = bound(idleInterest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        vault.deposit(deposit, address(adapter));
        asset.transfer(address(vault), idleInterest);

        uint256 expectedInterestPerSecond = boundInterestPerSecond(idleInterest, deposit, elapsed);
        assertEq(onchainVic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
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

        vault.deposit(deposit, address(adapter));
        asset.transfer(address(morphoVaultV1), vaultInterest);
        asset.transfer(address(vault), idleInterest);
        uint256 realVaultInterest = vaultInterest * deposit / (deposit + 1); // account for the virtual share.

        uint256 expectedInterestPerSecond = boundInterestPerSecond(realVaultInterest + idleInterest, deposit, elapsed);
        assertEq(onchainVic.interestPerSecond(deposit, elapsed), expectedInterestPerSecond, "interest per second");
    }

    function testInterestPerSecondZero(uint256 deposit, uint256 loss, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        loss = bound(loss, 1, deposit);
        elapsed = bound(elapsed, 1, 2 ** 63);

        vault.deposit(deposit, address(adapter));
        vm.prank(address(morphoVaultV1));
        asset.transfer(address(0xdead), loss);

        assertEq(onchainVic.interestPerSecond(deposit, elapsed), 0, "interest per second");
    }

    function testCreateOnchainVic() public {
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(OnchainVic).creationCode, abi.encode(address(vault))));
        address expectedVic = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(factory), bytes32(0), initCodeHash))))
        );

        vm.mockCall(
            address(adapter), abi.encodeCall(IMorphoVaultV1Adapter.morphoVaultV1, ()), abi.encode(morphoVaultV1)
        );
        vm.expectEmit();
        emit IOnchainVicFactory.CreateOnchainVic(expectedVic, address(vault));
        address newVic = factory.createOnchainVic(address(vault));

        assertEq(newVic, expectedVic, "createOnchainVic returned wrong address");
        assertTrue(factory.isOnchainVic(newVic), "Factory did not mark vic as valid");
        assertEq(factory.onchainVic(address(vault)), newVic, "Mapping not updated");
        assertEq(OnchainVic(newVic).parentVault(), address(vault), "Vic initialized incorrectly");
        assertEq(OnchainVic(newVic).asset(), address(asset), "Vic initialized incorrectly");
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
