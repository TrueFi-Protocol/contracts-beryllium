// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20WithDecimals} from "../interfaces/IERC20WithDecimals.sol";
import {BasePortfolio, IBasePortfolio} from "../BasePortfolio.sol";
import {IProtocolConfig} from "../interfaces/IProtocolConfig.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";

contract BasePortfolioImplementation is BasePortfolio {
    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
        uint256 _managerFee
    ) external initializer {
        __BasePortfolio_init(_protocolConfig, _duration, _asset, msg.sender, _managerFee);
        __ERC20_init("BasePortfolio", "BP");
    }

    function convertToAssets(uint256) public pure returns (uint256) {
        return 0;
    }

    function convertToShares(uint256) public pure override returns (uint256 shares) {
        return 0;
    }

    function maxRedeem(address) public pure returns (uint256) {
        return 0;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return 0;
    }

    function maxMint(address) external pure returns (uint256) {
        return 0;
    }

    function previewMint(uint256) external pure returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        return 0;
    }

    function redeem(
        uint256,
        address,
        address
    ) external pure returns (uint256) {
        return 0;
    }
}
