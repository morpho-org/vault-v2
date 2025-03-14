// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

struct ProtocolFee {
    uint96 fee;
    address feeRecipient;
}

interface IVaultV2Factory {
    function owner() external view returns (address);
    function protocolFee() external view returns (uint96);
    function protocolFeeRecipient() external view returns (address);
    function isVaultV2(address) external view returns (bool);
    function setOwner(address) external;
    function setProtocolFee(uint96) external;
    function setProtocolFeeRecipient(address) external;
    function createVaultV2(address, address, address, address, string memory, string memory)
        external
        returns (address);
}
