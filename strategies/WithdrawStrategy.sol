// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";

contract WithdrawStrategy is IWithdrawStrategy {
    function maxWithdraw(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function onWithdraw(
        address,
        uint256,
        address,
        address
    ) external pure returns (bool) {
        return true;
    }
}
