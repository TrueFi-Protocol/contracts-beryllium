// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDepositStrategy} from "../interfaces/IDepositStrategy.sol";
import {IPortfolio, IERC20WithDecimals} from "../interfaces/IPortfolio.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DepositStrategy is IDepositStrategy {
    function onDeposit(
        address,
        uint256 assets,
        address
    ) external returns (uint256, uint256) {
        return (IPortfolio(msg.sender).convertToShares(assets), 0);
    }

    function onMint(
        address,
        uint256 shares,
        address
    ) external view returns (uint256, uint256) {
        return (_previewMint(shares), 0);
    }

    function previewDepositFee(uint256) external pure returns (uint256) {
        return 0;
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return _previewMint(shares);
    }

    function _previewMint(uint256 shares) internal view returns (uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IERC20WithDecimals(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return shares;
        } else {
            return Math.ceilDiv((shares * totalAssets), totalSupply);
        }
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external view returns (uint256) {
        return IPortfolio(msg.sender).convertToShares(IPortfolio(msg.sender).maxSize() - IPortfolio(msg.sender).totalAssets());
    }
}
