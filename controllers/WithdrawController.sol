// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {IWithdrawController} from "../interfaces/IWithdrawController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract WithdrawController is IWithdrawController, Initializable {
    function initialize() external initializer {}

    function maxWithdraw(address owner) external view returns (uint256) {
        IPortfolio portfolio = IPortfolio(msg.sender);
        return Math.min(previewRedeem(portfolio.balanceOf(owner)), portfolio.liquidAssets());
    }

    function maxRedeem(address owner) external view returns (uint256) {
        IPortfolio portfolio = IPortfolio(msg.sender);
        return Math.min(portfolio.balanceOf(owner), previewWithdraw(portfolio.liquidAssets()));
    }

    function onWithdraw(
        address,
        uint256 assets,
        address,
        address
    ) external view returns (uint256, uint256) {
        return (previewWithdraw(assets), 0);
    }

    function onRedeem(
        address,
        uint256 shares,
        address,
        address
    ) external view returns (uint256, uint256) {
        return (previewRedeem(shares), 0);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return IPortfolio(msg.sender).convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
        if (totalAssets == 0) {
            return 0;
        } else {
            return Math.ceilDiv(assets * totalSupply, totalAssets);
        }
    }
}
