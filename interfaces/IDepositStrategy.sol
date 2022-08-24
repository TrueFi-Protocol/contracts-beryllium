// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDepositStrategy {
    function onDeposit(
        address sender,
        uint256 amount,
        address receiver
    ) external returns (bool, uint256);

    function previewDepositFee(uint256 assetsBeforeFee) external view returns (uint256 fee);

    function previewMintFee(uint256 assetsBeforeFee) external view returns (uint256 fee);

    function maxDeposit(address sender) external view returns (uint256 assets);
}
