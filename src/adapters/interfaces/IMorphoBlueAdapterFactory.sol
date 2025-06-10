// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IMorphoBlueAdapterFactory {
    /* EVENTS */

    event CreateMorphoBlueAdapter(address indexed vault, address indexed morphoBlueAdapter);

    /* FUNCTIONS */

    function morphoBlueAdapter(address vault, address morpho, address irm) external view returns (address);
    function isMorphoBlueAdapter(address adapter) external view returns (bool);
    function createMorphoBlueAdapter(address vault, address morpho, address irm) external returns (address);
}
