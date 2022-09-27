// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDepositStrategy} from "../interfaces/IDepositStrategy.sol";
import {IERC4626, IERC20WithDecimals} from "../interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DepositStrategy is IDepositStrategy {
    function onDeposit(
        address,
        uint256,
        address
    ) external pure returns (bool, uint256) {
        return (true, 0);
    }

    function onMint(
        address,
        uint256 shares,
        address
    ) external returns (uint256, uint256) {
        uint256 totalAssets = IERC4626(msg.sender).totalAssets();
        uint256 totalSupply = IERC20WithDecimals(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return (shares, 0);
        } else {
            return (Math.ceilDiv((shares * totalAssets), totalSupply), 0);
        }
    }

    function previewDepositFee(uint256) external pure returns (uint256) {
        return 0;
    }

    function previewMintFee(uint256) external pure returns (uint256) {
        return 0;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
