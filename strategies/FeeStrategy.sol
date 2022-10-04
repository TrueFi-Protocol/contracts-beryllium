// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFeeStrategy} from "../interfaces/IFeeStrategy.sol";

contract FeeStrategy is IFeeStrategy {
    function managerFeeRate() external pure returns (uint256) {
        return 0;
    }
}
