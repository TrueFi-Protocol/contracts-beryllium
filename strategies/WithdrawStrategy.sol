// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC4626, IERC20WithDecimals} from "../interfaces/IERC4626.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawStrategy is IWithdrawStrategy {
    function maxWithdraw(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function onWithdraw(
        address,
        uint256,
        address,
        address
    ) external pure returns (bool, uint256) {
        return (true, 0);
    }

    function onRedeem(
        address,
        uint256 shares,
        address,
        address
    ) external returns (uint256, uint256) {
        uint256 totalAssets = IERC4626(msg.sender).totalAssets();
        uint256 totalSupply = IERC20WithDecimals(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return (0, 0);
        } else {
            return (((shares * totalAssets) / totalSupply), 0);
        }
    }

    function previewRedeemFee(uint256) external pure returns (uint256) {
        return 0;
    }

    function previewWithdrawFee(uint256) external pure returns (uint256) {
        return 0;
    }
}
