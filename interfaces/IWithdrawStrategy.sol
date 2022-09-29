// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IWithdrawStrategy {
    function maxWithdraw(address owner) external view returns (uint256);

    function onWithdraw(
        address sender,
        uint256 amount,
        address receiver,
        address owner
    ) external returns (bool, uint256);

    function onRedeem(
        address sender,
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets, uint256 fee);

    function previewWithdrawFee(uint256 assetsBeforeFee) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);
}
