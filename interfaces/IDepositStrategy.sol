// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDepositStrategy {
    function isDepositAllowed(
        address sender,
        uint256 amount,
        address receiver
    ) external view returns (bool);

    function maxDeposit(address sender) external view returns (uint256);
}
