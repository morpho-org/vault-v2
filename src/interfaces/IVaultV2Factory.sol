// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

struct ProtocolFee {
    uint96 fee;
    address feeRecipient;
}

interface IVaultV2FactoryBase {
    function owner() external view returns (address);
    function isVaultV2(address) external view returns (bool);
    function setOwner(address) external;
    function setProtocolFee(ProtocolFee memory) external;
    function createVaultV2(address, address, address, address, string memory, string memory)
        external
        returns (address);
}

interface IVaultV2FactoryStaticTyping is IVaultV2FactoryBase {
    function protocolFee() external view returns (uint96, address);
}

interface IVaultV2Factory is IVaultV2FactoryBase {
    function protocolFee() external view returns (ProtocolFee memory);
}
