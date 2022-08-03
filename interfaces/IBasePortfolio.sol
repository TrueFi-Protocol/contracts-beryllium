// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IAccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "./IERC4626.sol";

interface IBasePortfolio is IAccessControlEnumerableUpgradeable, IERC4626 {
    function MANAGER_ROLE() external view returns (bytes32);

    function endDate() external view returns (uint256);

    function deposit(uint256 amount, address sender) external;

    function withdraw(uint256 shares, address sender) external;
}
