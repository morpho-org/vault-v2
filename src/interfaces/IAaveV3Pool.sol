// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IAaveV3Pool
/// @notice Minimal Aave V3 Pool interface for supply/withdraw operations
interface IAaveV3Pool {
    /// @notice Supply assets to Aave V3
    /// @param asset The address of the underlying asset to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address that will receive the aTokens
    /// @param referralCode Code used to register the integrator (0 for none)
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /// @notice Withdraw assets from Aave V3
    /// @param asset The address of the underlying asset to withdraw
    /// @param amount The amount to withdraw (use type(uint256).max for all)
    /// @param to The address that will receive the underlying
    /// @return The final amount withdrawn
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
