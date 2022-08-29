// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFeeStrategy {
    function managerFeeBeneficiary() external view returns (address);

    function managerFeeRate() external view returns (uint256);
}
