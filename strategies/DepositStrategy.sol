// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBasePortfolio} from "../interfaces/IBasePortfolio.sol";
import {IDepositStrategy} from "../interfaces/IDepositStrategy.sol";

contract DepositStrategy is IDepositStrategy {
    function deposit(IBasePortfolio portfolio, uint256 amount) public {
        portfolio.deposit(amount, msg.sender);
    }

    function isDepositAllowed(
        address,
        uint256,
        address
    ) external pure returns (bool) {
        return true;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
