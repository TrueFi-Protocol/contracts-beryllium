// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IWithdrawStrategy {
    function isWithdrawAllowed(
        address sender,
        uint256 amount,
        address receiver,
        address owner
    ) external view returns (bool);

    function maxWithdraw(address owner) external view returns (uint256);
}
