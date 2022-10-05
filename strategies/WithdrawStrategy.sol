// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawStrategy is IWithdrawStrategy {
    function maxWithdraw(address owner) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToAssets(IPortfolio(msg.sender).balanceOf(owner));
    }

    function maxRedeem(address) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToShares(IPortfolio(msg.sender).liquidAssets());
    }

    function onWithdraw(
        address,
        uint256 assets,
        address,
        address
    ) external view returns (uint256, uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
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
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return (0, 0);
        } else {
            return (((shares * totalAssets) / totalSupply), 0);
        }
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
        if (totalAssets == 0) {
            return 0;
        } else {
            return Math.ceilDiv(assets * totalSupply, totalAssets);
        }
    }
}
