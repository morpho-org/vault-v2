// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IMorphoBlueAdapterFactory {
    /* EVENTS */

    event CreateMorphoBlueAdapter(address indexed vault, address indexed morphoBlueAdapter);

    /* FUNCTIONS */

    function createMorphoBlueAdapter(address vault) external returns (address);
    function morphoBlueAdapter(address vault) external view returns (address);
    function isMorphoBlueAdapter(address adapter) external view returns (bool);
    function morpho() external view returns (address);
}
