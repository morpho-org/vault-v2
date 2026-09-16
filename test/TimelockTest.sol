// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Timelock} from "../src/Timelock.sol";
import {ITimelock, Operation, TimelockStatus, TIMELOCK_OPERATION_SELECTOR} from "../src/interfaces/ITimelock.sol";

contract TimelockAccountMock {
    ITimelock public immutable timelock;
    address public immutable curator;
    uint256 public value;

    constructor(ITimelock _timelock) {
        timelock = _timelock;
        curator = msg.sender;
    }

    function timelockOperation(Operation op, bytes32 key, bytes calldata data) external {
        if (op == Operation.Submit || op == Operation.Revoke) require(msg.sender == curator);
        else timelock.useTimelock(msg.data);
        timelock.operation(op, key, data);
    }

    function timelockStatus(bytes calldata data) external view returns (TimelockStatus memory) {
        return timelock.status(address(this), data);
    }

    function setValue(uint256 newValue) external {
        timelock.useTimelock(msg.data);
        value = newValue;
    }

    function failingCall() external {
        timelock.useTimelock(msg.data);
        revert("account failure");
    }
}

contract TimelockTest is Test {
    Timelock internal timelock;
    TimelockAccountMock internal account;
    TimelockAccountMock internal other;

    function setUp() public {
        timelock = new Timelock();
        account = new TimelockAccountMock(timelock);
        other = new TimelockAccountMock(timelock);
    }

    function managementCall(Operation op, bytes32 key, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockAccountMock.timelockOperation, (op, key, data));
    }

    function managementKey(Operation op) internal view returns (bytes32) {
        return timelock.getKey(managementCall(op, 0, ""));
    }

    function configure(Operation op, bytes32 key, bytes memory data) internal {
        account.timelockOperation(Operation.Submit, 0, managementCall(op, key, data));
        account.timelockOperation(op, key, data);
    }

    function testKeys(bytes4 selector) public view {
        vm.assume(selector != TIMELOCK_OPERATION_SELECTOR);
        assertEq(timelock.getKey(abi.encodePacked(selector)), bytes32(selector));
        assertEq(TimelockAccountMock.timelockOperation.selector, TIMELOCK_OPERATION_SELECTOR);
        for (uint256 i; i <= uint256(Operation.Abdicate); i++) {
            bytes32 key = managementKey(Operation(i));
            assertEq(key, bytes32(i + 1));
            assertNotEq(key, bytes32(selector));
        }
    }

    function testIndependentNamespaces(uint256 value) public {
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (value));
        account.timelockOperation(Operation.Submit, 0, data);
        other.timelockOperation(Operation.Submit, 0, data);
        account.timelockOperation(Operation.Revoke, 0, data);
        assertEq(account.timelockStatus(data).executableAt, 0);
        assertEq(other.timelockStatus(data).executableAt, block.timestamp);
        other.setValue(value);

        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(5 days));
        configure(Operation.Abdicate, TimelockAccountMock.setValue.selector, "");
        assertEq(account.timelockStatus(data).delay, 5 days);
        assertTrue(account.timelockStatus(data).abdicated);
        assertEq(other.timelockStatus(data).delay, 0);
        assertFalse(other.timelockStatus(data).abdicated);
    }

    function testDirectCallsCannotTouchAccount(uint256 value) public {
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (value));
        account.timelockOperation(Operation.Submit, 0, data);
        vm.expectRevert(ITimelock.Invalid.selector);
        timelock.useTimelock(data);
        vm.expectRevert(ITimelock.DataNotTimelocked.selector);
        timelock.operation(Operation.Revoke, 0, data);

        timelock.operation(Operation.Submit, 0, data);
        timelock.useTimelock(data);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
        account.setValue(value);
        assertEq(account.value(), value);
    }

    function testDirectConfigurationCannotTouchAccount(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        uint256 duration = op == Operation.IncreaseTimelock ? 5 days : 0;
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(duration);
        bytes memory data = managementCall(op, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        timelock.operation(op, key, parameters);
        bytes memory selector = abi.encodePacked(TimelockAccountMock.setValue.selector);
        assertEq(timelock.status(address(this), selector).delay, duration);
        assertEq(timelock.status(address(this), selector).abdicated, op == Operation.Abdicate);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
        assertEq(account.timelockStatus(selector).delay, 0);
        assertFalse(account.timelockStatus(selector).abdicated);
        account.timelockOperation(op, key, parameters);
        assertEq(account.timelockStatus(data).executableAt, 0);
        assertEq(account.timelockStatus(selector).delay, duration);
        assertEq(account.timelockStatus(selector).abdicated, op == Operation.Abdicate);
    }

    function testManagementRequiresSubmission(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        vm.expectRevert(ITimelock.Invalid.selector);
        account.timelockOperation(op, TimelockAccountMock.setValue.selector, abi.encode(0));
    }

    function testCannotDispatchUseTimelock(uint8 op_) public {
        op_ = uint8(bound(op_, uint256(Operation.Abdicate) + 1, type(uint8).max));
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (1));
        account.timelockOperation(Operation.Submit, 0, data);
        bytes memory dispatched = abi.encodeCall(ITimelock.useTimelock, (data));
        (bool success,) =
            address(account).call(abi.encodeWithSelector(TIMELOCK_OPERATION_SELECTOR, op_, bytes32(0), dispatched));
        assertFalse(success);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
    }

    function testSeparateManagementDelays() public {
        configure(Operation.IncreaseTimelock, managementKey(Operation.Abdicate), abi.encode(9 days));
        configure(Operation.IncreaseTimelock, managementKey(Operation.IncreaseTimelock), abi.encode(5 days));
        bytes memory increase =
            managementCall(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(7 days));
        bytes memory abdicate = managementCall(Operation.Abdicate, TimelockAccountMock.setValue.selector, "");
        account.timelockOperation(Operation.Submit, 0, increase);
        account.timelockOperation(Operation.Submit, 0, abdicate);
        assertEq(account.timelockStatus(increase).executableAt, block.timestamp + 5 days);
        assertEq(account.timelockStatus(abdicate).executableAt, block.timestamp + 9 days);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        account.timelockOperation(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(7 days));
        skip(5 days);
        account.timelockOperation(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(7 days));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        account.timelockOperation(Operation.Abdicate, TimelockAccountMock.setValue.selector, "");
        skip(4 days);
        account.timelockOperation(Operation.Abdicate, TimelockAccountMock.setValue.selector, "");
    }

    function testDecreaseUsesTargetDelay(uint256 delay) public {
        delay = bound(delay, 1, 3650 days);
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(delay));
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(0);
        bytes memory data = managementCall(Operation.DecreaseTimelock, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp + delay);
        assertEq(account.timelockStatus(data).delay, 0);
        skip(delay - 1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        account.timelockOperation(Operation.DecreaseTimelock, key, parameters);
        skip(1);
        account.timelockOperation(Operation.DecreaseTimelock, key, parameters);
        assertEq(account.timelockStatus(abi.encodePacked(TimelockAccountMock.setValue.selector)).delay, 0);
    }

    function testDecreaseManagementDelayUsesTarget() public {
        configure(Operation.IncreaseTimelock, managementKey(Operation.IncreaseTimelock), abi.encode(8 days));
        bytes32 key = managementKey(Operation.IncreaseTimelock);
        bytes memory parameters = abi.encode(0);
        bytes memory data = managementCall(Operation.DecreaseTimelock, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp + 8 days);
        skip(8 days);
        account.timelockOperation(Operation.DecreaseTimelock, key, parameters);
        assertEq(account.timelockStatus(managementCall(Operation.IncreaseTimelock, 0, "")).delay, 0);
    }

    function testIncreasingDelayDoesNotReschedule() public {
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(5 days));
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (1));
        account.timelockOperation(Operation.Submit, 0, data);
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(20 days));
        assertEq(account.timelockStatus(data).executableAt, block.timestamp + 5 days);
        skip(5 days);
        account.setValue(1);
    }

    function testAbdicationBlocksPendingCalls() public {
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (1));
        account.timelockOperation(Operation.Submit, 0, data);
        configure(Operation.Abdicate, TimelockAccountMock.setValue.selector, "");
        vm.expectRevert(ITimelock.Abdicated.selector);
        account.setValue(1);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
        account.timelockOperation(Operation.Revoke, 0, data);
        account.timelockOperation(Operation.Submit, 0, data);
        vm.expectRevert(ITimelock.Abdicated.selector);
        account.setValue(1);
    }

    function testAbdicateIndividualManagementOperation(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(0);
        bytes memory data = managementCall(op, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        configure(Operation.Abdicate, managementKey(op), "");
        vm.expectRevert(ITimelock.Abdicated.selector);
        account.timelockOperation(op, key, parameters);
        assertTrue(account.timelockStatus(data).abdicated);
        Operation otherOp = op == Operation.IncreaseTimelock ? Operation.DecreaseTimelock : Operation.IncreaseTimelock;
        configure(otherOp, key, parameters);
    }

    function testCannotSetDecreaseDelay() public {
        bytes32 key = managementKey(Operation.DecreaseTimelock);
        bytes memory parameters = abi.encode(0);
        for (uint256 i = uint256(Operation.IncreaseTimelock); i <= uint256(Operation.DecreaseTimelock); i++) {
            account.timelockOperation(Operation.Submit, 0, managementCall(Operation(i), key, parameters));
            vm.expectRevert(ITimelock.AutomaticallyTimelocked.selector);
            account.timelockOperation(Operation(i), key, parameters);
        }
    }

    function testConfigurationFailureRestoresPending() public {
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(2 days));
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(1 days);
        bytes memory data = managementCall(Operation.IncreaseTimelock, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        vm.expectRevert(ITimelock.TimelockNotIncreasing.selector);
        account.timelockOperation(Operation.IncreaseTimelock, key, parameters);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
        assertEq(account.timelockStatus(abi.encodePacked(TimelockAccountMock.setValue.selector)).delay, 2 days);
    }

    function testAccountFailureRestoresPending() public {
        bytes memory data = abi.encodeCall(TimelockAccountMock.failingCall, ());
        account.timelockOperation(Operation.Submit, 0, data);
        vm.expectRevert(bytes("account failure"));
        account.failingCall();
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
    }

    function testExactManagementCalldata() public {
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(1 days);
        bytes memory data = managementCall(Operation.IncreaseTimelock, key, parameters);
        bytes memory extended = bytes.concat(data, hex"1234");
        account.timelockOperation(Operation.Submit, 0, data);
        (bool success, bytes memory result) = address(account).call(extended);
        assertFalse(success);
        assertEq(bytes4(result), ITimelock.Invalid.selector);
        account.timelockOperation(Operation.Submit, 0, extended);
        (success,) = address(account).call(extended);
        assertTrue(success);
        assertEq(account.timelockStatus(extended).executableAt, 0);
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
        account.timelockOperation(Operation.IncreaseTimelock, key, parameters);
    }

    function testExactNoncanonicalManagementCalldata(uint8 op_, bytes32 padding) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(3 days));
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = abi.encode(op == Operation.IncreaseTimelock ? 4 days : 0);
        bytes memory data = managementCall(op, key, parameters);
        bytes memory extended = bytes.concat(
            TIMELOCK_OPERATION_SELECTOR, abi.encode(op, key, uint256(128), padding, parameters.length), parameters
        );
        account.timelockOperation(Operation.Submit, 0, data);
        (bool success, bytes memory result) = address(account).call(extended);
        assertFalse(success);
        assertEq(bytes4(result), ITimelock.Invalid.selector);
        account.timelockOperation(Operation.Submit, 0, extended);
        uint256 executableAt = block.timestamp + (op == Operation.DecreaseTimelock ? 3 days : 0);
        assertEq(account.timelockStatus(extended).executableAt, executableAt);
        vm.warp(executableAt);
        (success,) = address(account).call(extended);
        assertTrue(success);
        assertEq(account.timelockStatus(extended).executableAt, 0);
        assertEq(account.timelockStatus(data).executableAt, executableAt);
    }

    function testExactSetterCalldata() public {
        bytes memory data = abi.encodeCall(TimelockAccountMock.setValue, (1));
        bytes memory extended = bytes.concat(data, hex"1234");
        account.timelockOperation(Operation.Submit, 0, extended);
        vm.expectRevert(ITimelock.Invalid.selector);
        account.setValue(1);
        (bool success,) = address(account).call(extended);
        assertTrue(success);
        assertEq(account.value(), 1);
        assertEq(account.timelockStatus(extended).executableAt, 0);
    }

    function testMaximumDelayBlocksSubmission() public {
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(type(uint256).max));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        account.timelockOperation(Operation.Submit, 0, abi.encodeCall(TimelockAccountMock.setValue, (1)));
    }

    function testMalformedDecreaseRestoresPending() public {
        configure(Operation.IncreaseTimelock, TimelockAccountMock.setValue.selector, abi.encode(2 days));
        bytes32 key = TimelockAccountMock.setValue.selector;
        bytes memory parameters = "";
        bytes memory data = managementCall(Operation.DecreaseTimelock, key, parameters);
        account.timelockOperation(Operation.Submit, 0, data);
        uint256 executableAt = block.timestamp + 2 days;
        assertEq(account.timelockStatus(data).executableAt, executableAt);
        vm.warp(executableAt);
        vm.expectRevert();
        account.timelockOperation(Operation.DecreaseTimelock, key, parameters);
        assertEq(account.timelockStatus(data).executableAt, executableAt);
        assertEq(account.timelockStatus(abi.encodePacked(TimelockAccountMock.setValue.selector)).delay, 2 days);
    }

    function testMalformedConfigurationRestoresPending() public {
        bytes memory data = managementCall(Operation.IncreaseTimelock, 0, hex"01");
        account.timelockOperation(Operation.Submit, 0, data);
        vm.expectRevert();
        account.timelockOperation(Operation.IncreaseTimelock, 0, hex"01");
        assertEq(account.timelockStatus(data).executableAt, block.timestamp);
    }
}
