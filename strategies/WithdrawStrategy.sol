// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBasePortfolio} from "../interfaces/IBasePortfolio.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";

contract WithdrawStrategy is IWithdrawStrategy {
    function withdraw(IBasePortfolio portfolio, uint256 shares) public {
        portfolio.withdraw(shares, msg.sender);
    }

    function isWithdrawAllowed(
        address sender,
        address receiver,
        uint256 amount
    ) external view returns (bool) {
        return true;
    }

    function maxWithdraw(address) external view returns (uint256) {
        return type(uint256).max;
    }
}
