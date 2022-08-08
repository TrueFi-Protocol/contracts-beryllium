// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithDecimals} from "./IERC20WithDecimals.sol";

interface IERC4626 {
    function asset() external returns (IERC20WithDecimals asset);

    function totalAssets() external returns (uint256 totalManagedAssets);

    function convertToShares(uint256 assets) external returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function maxRedeem(address owner) external view returns (uint256 shares);

    function maxDeposit(address receiver) external view returns (uint256);

    function maxMint(address receiver) external view returns (uint256);

    function previewMint(uint256 shares) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
}
