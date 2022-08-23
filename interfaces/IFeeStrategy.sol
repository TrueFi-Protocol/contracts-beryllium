// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFeeStrategy {
    function managerFeeBeneficiary() external view returns (address);

    function managerFee() external view returns (uint256);
}
