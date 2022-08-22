// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFeeStrategy {
    function managerFee() external view returns (uint256);
}
