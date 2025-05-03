// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IManualInterestControllerFactory {
    function isManualInterestController(address) external view returns (bool);
    function createManualInterestController(address, bytes32) external returns (address);
}
