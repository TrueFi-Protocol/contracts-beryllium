// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDepositController} from "../interfaces/IDepositController.sol";
import {ILenderVerifier} from "../interfaces/ILenderVerifier.sol";
import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DepositController is IDepositController, Initializable {
    ILenderVerifier public lenderVerifier;

    function initialize(ILenderVerifier _lenderVerifier) external virtual initializer {
        lenderVerifier = _lenderVerifier;
    }

    function maxDeposit(address receiver) public view virtual returns (uint256) {
        if (!lenderVerifier.isAllowed(receiver)) {
            return 0;
        }
        return IPortfolio(msg.sender).maxSize() - IPortfolio(msg.sender).totalAssets();
    }

    function maxMint(address receiver) public view virtual returns (uint256) {
        if (!lenderVerifier.isAllowed(receiver)) {
            return 0;
        }
        return previewDeposit(maxDeposit(receiver));
    }

    function onDeposit(
        address,
        uint256 assets,
        address receiver
    ) public view virtual returns (uint256, uint256) {
        if (!lenderVerifier.isAllowed(receiver)) {
            return (0, 0);
        }
        return (previewDeposit(assets), 0);
    }

    function onMint(
        address,
        uint256 shares,
        address receiver
    ) public view virtual returns (uint256, uint256) {
        if (!lenderVerifier.isAllowed(receiver)) {
            return (0, 0);
        }
        return (previewMint(shares), 0);
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return IPortfolio(msg.sender).convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 totalAssets = IPortfolio(msg.sender).totalAssets();
        uint256 totalSupply = IPortfolio(msg.sender).totalSupply();
        if (totalSupply == 0) {
            return shares;
        } else {
            return Math.ceilDiv((shares * totalAssets), totalSupply);
        }
    }
}
