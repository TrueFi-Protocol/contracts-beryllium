// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDepositStrategy} from "../interfaces/IDepositStrategy.sol";
import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DepositStrategy is IDepositStrategy {
    function maxDeposit(address sender) external view returns (uint256) {
        return _maxDeposit(sender);
    }

    function _maxDeposit(address) internal view returns (uint256) {
        return IPortfolio(msg.sender).maxSize() - IPortfolio(msg.sender).totalAssets();
    }

    function maxMint(address sender) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToShares(_maxDeposit(sender));
    }

    function onDeposit(
        address,
        uint256 assets,
        address
    ) external view returns (uint256, uint256) {
        return (IPortfolio(msg.sender).convertToShares(assets), 0);
    }

    function onMint(
        address,
        uint256 shares,
        address
    ) external view returns (uint256, uint256) {
        return (_previewMint(shares), 0);
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        return IPortfolio(msg.sender).convertToShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return _previewMint(shares);
    }

    function _previewMint(uint256 shares) internal view returns (uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return shares;
        } else {
            return Math.ceilDiv((shares * totalAssets), totalSupply);
        }
    }
}
