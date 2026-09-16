// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Timelock} from "../src/Timelock.sol";
import {ITimelock, Operation, TimelockStatus, TIMELOCK_OPERATION_SELECTOR} from "../src/interfaces/ITimelock.sol";

contract TimelockConsumerMock {
    ITimelock public immutable timelock;
    address public immutable curator;
    uint256 public value;

    constructor(ITimelock _timelock) {
        timelock = _timelock;
        curator = msg.sender;
    }

    function timelockOperation(Operation op, bytes calldata data) external {
        if (op == Operation.Submit || op == Operation.Revoke) require(msg.sender == curator);
        else timelock.useTimelock(msg.data);
        timelock.operation(op, data);
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
        revert("consumer failure");
    }
}

contract TimelockTest is Test {
    Timelock internal timelock;
    TimelockConsumerMock internal consumer;
    TimelockConsumerMock internal other;

    function setUp() public {
        timelock = new Timelock();
        consumer = new TimelockConsumerMock(timelock);
        other = new TimelockConsumerMock(timelock);
    }

    function managementCall(Operation op, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockConsumerMock.timelockOperation, (op, data));
    }

    function managementKey(Operation op) internal view returns (bytes32) {
        return timelock.getKey(managementCall(op, ""));
    }

    function configure(Operation op, bytes memory data) internal {
        consumer.timelockOperation(Operation.Submit, managementCall(op, data));
        consumer.timelockOperation(op, data);
    }

    function testKeys(bytes4 selector) public view {
        vm.assume(selector != TIMELOCK_OPERATION_SELECTOR);
        assertEq(timelock.getKey(abi.encodePacked(selector)), bytes32(selector));
        assertEq(TimelockConsumerMock.timelockOperation.selector, TIMELOCK_OPERATION_SELECTOR);
        for (uint256 i; i <= uint256(Operation.Abdicate); i++) {
            bytes32 key = managementKey(Operation(i));
            assertEq(key, bytes32(i + 1));
            assertNotEq(key, bytes32(selector));
        }
    }

    function testIndependentNamespaces(uint256 value) public {
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (value));
        consumer.timelockOperation(Operation.Submit, data);
        other.timelockOperation(Operation.Submit, data);
        consumer.timelockOperation(Operation.Revoke, data);
        assertEq(consumer.timelockStatus(data).executableAt, 0);
        assertEq(other.timelockStatus(data).executableAt, block.timestamp);
        other.setValue(value);

        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 5 days));
        configure(Operation.Abdicate, abi.encode(TimelockConsumerMock.setValue.selector));
        assertEq(consumer.timelockStatus(data).delay, 5 days);
        assertTrue(consumer.timelockStatus(data).abdicated);
        assertEq(other.timelockStatus(data).delay, 0);
        assertFalse(other.timelockStatus(data).abdicated);
    }

    function testDirectCallsCannotTouchConsumer(uint256 value) public {
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (value));
        consumer.timelockOperation(Operation.Submit, data);
        vm.expectRevert(ITimelock.Invalid.selector);
        timelock.useTimelock(data);
        vm.expectRevert(ITimelock.DataNotTimelocked.selector);
        timelock.operation(Operation.Revoke, data);

        timelock.operation(Operation.Submit, data);
        timelock.useTimelock(data);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
        consumer.setValue(value);
        assertEq(consumer.value(), value);
    }

    function testDirectConfigurationCannotTouchConsumer(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        uint256 duration = op == Operation.IncreaseTimelock ? 5 days : 0;
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector, duration);
        bytes memory data = managementCall(op, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        timelock.operation(op, parameters);
        bytes memory selector = abi.encodePacked(TimelockConsumerMock.setValue.selector);
        assertEq(timelock.status(address(this), selector).delay, duration);
        assertEq(timelock.status(address(this), selector).abdicated, op == Operation.Abdicate);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
        assertEq(consumer.timelockStatus(selector).delay, 0);
        assertFalse(consumer.timelockStatus(selector).abdicated);
        consumer.timelockOperation(op, parameters);
        assertEq(consumer.timelockStatus(data).executableAt, 0);
        assertEq(consumer.timelockStatus(selector).delay, duration);
        assertEq(consumer.timelockStatus(selector).abdicated, op == Operation.Abdicate);
    }

    function testManagementRequiresSubmission(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        vm.expectRevert(ITimelock.Invalid.selector);
        consumer.timelockOperation(op, abi.encode(TimelockConsumerMock.setValue.selector, 0));
    }

    function testCannotDispatchUseTimelock(uint8 op_) public {
        op_ = uint8(bound(op_, uint256(Operation.Abdicate) + 1, type(uint8).max));
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (1));
        consumer.timelockOperation(Operation.Submit, data);
        bytes memory dispatched = abi.encodeCall(ITimelock.useTimelock, (data));
        (bool success,) =
            address(consumer).call(abi.encodeWithSelector(TIMELOCK_OPERATION_SELECTOR, op_, dispatched));
        assertFalse(success);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
    }

    function testSeparateManagementDelays() public {
        configure(Operation.IncreaseTimelock, abi.encode(managementKey(Operation.Abdicate), 9 days));
        configure(Operation.IncreaseTimelock, abi.encode(managementKey(Operation.IncreaseTimelock), 5 days));
        bytes memory increase =
            managementCall(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 7 days));
        bytes memory abdicate = managementCall(Operation.Abdicate, abi.encode(TimelockConsumerMock.setValue.selector));
        consumer.timelockOperation(Operation.Submit, increase);
        consumer.timelockOperation(Operation.Submit, abdicate);
        assertEq(consumer.timelockStatus(increase).executableAt, block.timestamp + 5 days);
        assertEq(consumer.timelockStatus(abdicate).executableAt, block.timestamp + 9 days);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        consumer.timelockOperation(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 7 days));
        skip(5 days);
        consumer.timelockOperation(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 7 days));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        consumer.timelockOperation(Operation.Abdicate, abi.encode(TimelockConsumerMock.setValue.selector));
        skip(4 days);
        consumer.timelockOperation(Operation.Abdicate, abi.encode(TimelockConsumerMock.setValue.selector));
    }

    function testDecreaseUsesTargetDelay(uint256 delay) public {
        delay = bound(delay, 1, 3650 days);
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, delay));
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector, 0);
        bytes memory data = managementCall(Operation.DecreaseTimelock, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp + delay);
        assertEq(consumer.timelockStatus(data).delay, 0);
        skip(delay - 1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        consumer.timelockOperation(Operation.DecreaseTimelock, parameters);
        skip(1);
        consumer.timelockOperation(Operation.DecreaseTimelock, parameters);
        assertEq(consumer.timelockStatus(abi.encodePacked(TimelockConsumerMock.setValue.selector)).delay, 0);
    }

    function testDecreaseManagementDelayUsesTarget() public {
        configure(Operation.IncreaseTimelock, abi.encode(managementKey(Operation.IncreaseTimelock), 8 days));
        bytes memory parameters = abi.encode(managementKey(Operation.IncreaseTimelock), 0);
        bytes memory data = managementCall(Operation.DecreaseTimelock, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp + 8 days);
        skip(8 days);
        consumer.timelockOperation(Operation.DecreaseTimelock, parameters);
        assertEq(consumer.timelockStatus(managementCall(Operation.IncreaseTimelock, "")).delay, 0);
    }

    function testIncreasingDelayDoesNotReschedule() public {
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 5 days));
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (1));
        consumer.timelockOperation(Operation.Submit, data);
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 20 days));
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp + 5 days);
        skip(5 days);
        consumer.setValue(1);
    }

    function testAbdicationBlocksPendingCalls() public {
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (1));
        consumer.timelockOperation(Operation.Submit, data);
        configure(Operation.Abdicate, abi.encode(TimelockConsumerMock.setValue.selector));
        vm.expectRevert(ITimelock.Abdicated.selector);
        consumer.setValue(1);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
        consumer.timelockOperation(Operation.Revoke, data);
        consumer.timelockOperation(Operation.Submit, data);
        vm.expectRevert(ITimelock.Abdicated.selector);
        consumer.setValue(1);
    }

    function testAbdicateIndividualManagementOperation(uint8 op_) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector, 0);
        bytes memory data = managementCall(op, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        configure(Operation.Abdicate, abi.encode(managementKey(op)));
        vm.expectRevert(ITimelock.Abdicated.selector);
        consumer.timelockOperation(op, parameters);
        assertTrue(consumer.timelockStatus(data).abdicated);
        Operation otherOp = op == Operation.IncreaseTimelock ? Operation.DecreaseTimelock : Operation.IncreaseTimelock;
        configure(otherOp, parameters);
    }

    function testCannotSetDecreaseDelay() public {
        bytes memory parameters = abi.encode(managementKey(Operation.DecreaseTimelock), 0);
        for (uint256 i = uint256(Operation.IncreaseTimelock); i <= uint256(Operation.DecreaseTimelock); i++) {
            consumer.timelockOperation(Operation.Submit, managementCall(Operation(i), parameters));
            vm.expectRevert(ITimelock.AutomaticallyTimelocked.selector);
            consumer.timelockOperation(Operation(i), parameters);
        }
    }

    function testConfigurationFailureRestoresPending() public {
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 2 days));
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector, 1 days);
        bytes memory data = managementCall(Operation.IncreaseTimelock, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        vm.expectRevert(ITimelock.TimelockNotIncreasing.selector);
        consumer.timelockOperation(Operation.IncreaseTimelock, parameters);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
        assertEq(consumer.timelockStatus(abi.encodePacked(TimelockConsumerMock.setValue.selector)).delay, 2 days);
    }

    function testConsumerFailureRestoresPending() public {
        bytes memory data = abi.encodeCall(TimelockConsumerMock.failingCall, ());
        consumer.timelockOperation(Operation.Submit, data);
        vm.expectRevert(bytes("consumer failure"));
        consumer.failingCall();
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
    }

    function testExactManagementCalldata() public {
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector, 1 days);
        bytes memory data = managementCall(Operation.IncreaseTimelock, parameters);
        bytes memory extended = bytes.concat(data, hex"1234");
        consumer.timelockOperation(Operation.Submit, data);
        (bool success, bytes memory result) = address(consumer).call(extended);
        assertFalse(success);
        assertEq(bytes4(result), ITimelock.Invalid.selector);
        consumer.timelockOperation(Operation.Submit, extended);
        (success,) = address(consumer).call(extended);
        assertTrue(success);
        assertEq(consumer.timelockStatus(extended).executableAt, 0);
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
        consumer.timelockOperation(Operation.IncreaseTimelock, parameters);
    }

    function testExactNoncanonicalManagementCalldata(uint8 op_, bytes32 padding) public {
        Operation op = Operation(bound(op_, uint256(Operation.IncreaseTimelock), uint256(Operation.Abdicate)));
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 3 days));
        bytes memory parameters =
            abi.encode(TimelockConsumerMock.setValue.selector, op == Operation.IncreaseTimelock ? 4 days : 0);
        bytes memory data = managementCall(op, parameters);
        bytes memory extended = bytes.concat(
            TIMELOCK_OPERATION_SELECTOR, abi.encode(op, uint256(96), padding, parameters.length), parameters
        );
        consumer.timelockOperation(Operation.Submit, data);
        (bool success, bytes memory result) = address(consumer).call(extended);
        assertFalse(success);
        assertEq(bytes4(result), ITimelock.Invalid.selector);
        consumer.timelockOperation(Operation.Submit, extended);
        uint256 executableAt = block.timestamp + (op == Operation.DecreaseTimelock ? 3 days : 0);
        assertEq(consumer.timelockStatus(extended).executableAt, executableAt);
        vm.warp(executableAt);
        (success,) = address(consumer).call(extended);
        assertTrue(success);
        assertEq(consumer.timelockStatus(extended).executableAt, 0);
        assertEq(consumer.timelockStatus(data).executableAt, executableAt);
    }

    function testExactSetterCalldata() public {
        bytes memory data = abi.encodeCall(TimelockConsumerMock.setValue, (1));
        bytes memory extended = bytes.concat(data, hex"1234");
        consumer.timelockOperation(Operation.Submit, extended);
        vm.expectRevert(ITimelock.Invalid.selector);
        consumer.setValue(1);
        (bool success,) = address(consumer).call(extended);
        assertTrue(success);
        assertEq(consumer.value(), 1);
        assertEq(consumer.timelockStatus(extended).executableAt, 0);
    }

    function testMaximumDelayBlocksSubmission() public {
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, type(uint256).max));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        consumer.timelockOperation(Operation.Submit, abi.encodeCall(TimelockConsumerMock.setValue, (1)));
    }

    function testMalformedDecreaseRestoresPending() public {
        configure(Operation.IncreaseTimelock, abi.encode(TimelockConsumerMock.setValue.selector, 2 days));
        bytes memory parameters = abi.encode(TimelockConsumerMock.setValue.selector);
        bytes memory data = managementCall(Operation.DecreaseTimelock, parameters);
        consumer.timelockOperation(Operation.Submit, data);
        uint256 executableAt = block.timestamp + 2 days;
        assertEq(consumer.timelockStatus(data).executableAt, executableAt);
        vm.warp(executableAt);
        vm.expectRevert();
        consumer.timelockOperation(Operation.DecreaseTimelock, parameters);
        assertEq(consumer.timelockStatus(data).executableAt, executableAt);
        assertEq(consumer.timelockStatus(abi.encodePacked(TimelockConsumerMock.setValue.selector)).delay, 2 days);
    }

    function testMalformedConfigurationRestoresPending() public {
        bytes memory data = managementCall(Operation.IncreaseTimelock, hex"01");
        consumer.timelockOperation(Operation.Submit, data);
        vm.expectRevert();
        consumer.timelockOperation(Operation.IncreaseTimelock, hex"01");
        assertEq(consumer.timelockStatus(data).executableAt, block.timestamp);
    }
}
