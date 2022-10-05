// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IProtocolConfig} from "./IProtocolConfig.sol";
import {IERC4626} from "./IERC4626.sol";
import {IDepositStrategy} from "./IDepositStrategy.sol";
import {IWithdrawStrategy} from "./IWithdrawStrategy.sol";
import {ITransferStrategy} from "./ITransferStrategy.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

interface IPortfolio is IERC4626, IERC165 {
    function maxSize() external view returns (uint256);

    function liquidAssets() external view returns (uint256);
}
