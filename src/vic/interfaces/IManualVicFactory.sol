// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IManualVicFactory {
    function isManualVic(address) external view returns (bool);
    function createManualVic(address, bytes32) external returns (address);
}
