// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawStrategy is IWithdrawStrategy {
    function maxWithdraw(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function onWithdraw(
        address,
        uint256 assets,
        address,
        address
    ) external view returns (uint256, uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IERC20Metadata(msg.sender).totalSupply();
        if (totalAssets == 0) {
            return (0, 0);
        } else {
            return (Math.ceilDiv((assets * totalSupply), totalAssets), 0);
        }
    }

    function onRedeem(
        address,
        uint256 shares,
        address,
        address
    ) external view returns (uint256, uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IERC20Metadata(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return (0, 0);
        } else {
            return (((shares * totalAssets) / totalSupply), 0);
        }
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToAssets(shares);
    }

    function previewWithdrawFee(uint256) external pure returns (uint256) {
        return 0;
    }
}
