// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {StringLib} from "../src/libraries/StringLib.sol";

contract StringLibTest is Test {
    string internal myString;
    uint256 myStringSlot;

    function setUp() public {
        assembly {
            sstore(myStringSlot.slot, myString.slot)
        }
        myString = "hello";
    }

    // function testShowShortStorageString() public view {
    //     bytes32 expectedEncoded;
    //     assembly {
    //         expectedEncoded := sload(myString.slot)
    //     }
    //     console.logBytes32(expectedEncoded);
    // }

    // function testShowShortMemoryString() public pure {
    //     string memory memString = "hello";
    //     console.log("length", bytes(memString).length);
    //     bytes32 str1;
    //     bytes32 str2;
    //     assembly {
    //         str1 := mload(memString)
    //         str2 := mload(add(memString, 32))
    //     }
    //     console.logBytes32(str1);
    //     console.logBytes32(str2);
    // }

    function testWriteToSlot() public {
        bytes32 expectedEncoded;
        assembly {
            expectedEncoded := sload(myString.slot)
        }

        string memory tempString = "hello";
        StringLib.writeStringToSlot(tempString, myStringSlot);
        bytes32 encoded;
        assembly {
            encoded := sload(myString.slot)
        }

        assertEq(encoded, expectedEncoded);
    }

    function testReadFromSlot() public view {
        string memory expectedString = "hello";

        assertEq(StringLib.readStringFromSlot(myStringSlot), expectedString);
    }
}
