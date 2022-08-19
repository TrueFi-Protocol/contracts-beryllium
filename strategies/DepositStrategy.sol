// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDepositStrategy} from "../interfaces/IDepositStrategy.sol";

contract DepositStrategy is IDepositStrategy {
    function onDeposit(
        address,
        uint256,
        address
    ) external pure returns (bool, uint256) {
        return (true, 0);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
