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
        address,
        uint256
    ) external view returns (bool) {
        return true;
    }

    function maxDeposit(address, address) external view returns (uint256) {
        return type(uint256).max;
    }
}
