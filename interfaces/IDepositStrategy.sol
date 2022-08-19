// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDepositStrategy {
    function onDeposit(
        address sender,
        uint256 amount,
        address receiver
    ) external returns (bool, uint256);

    function maxDeposit(address sender) external view returns (uint256);
}
