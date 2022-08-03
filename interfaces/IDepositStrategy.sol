// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDepositStrategy {
    function isDepositAllowed(
        address sender,
        address receiver,
        uint256 amount
    ) external view returns (bool);

    function maxDeposit(address sender, address receiver) external view returns (uint256);
}
