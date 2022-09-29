// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20WithDecimals} from "./IERC20WithDecimals.sol";
import {IProtocolConfig} from "./IProtocolConfig.sol";
import {IERC4626} from "./IERC4626.sol";
import {IDepositStrategy} from "./IDepositStrategy.sol";
import {IWithdrawStrategy} from "./IWithdrawStrategy.sol";
import {ITransferStrategy} from "./ITransferStrategy.sol";

interface IPortfolio is IERC4626 {
    function maxSize() external view returns (uint256);
}
