// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMerkleTreeVerifier} from "../lithium/interfaces/IMerkleTreeVerifier.sol";
import {IFlexiblePortfolio} from "../interfaces/IFlexiblePortfolio.sol";
import {DepositController} from "./DepositController.sol";

contract MerkleTreeVerifierDepositController is DepositController {
    using SafeERC20 for IERC20Metadata;

    IMerkleTreeVerifier public immutable verifier;
    uint256 public immutable allowListIndex;

    constructor(IMerkleTreeVerifier _verifier, uint256 _allowListIndex) {
        verifier = _verifier;
        allowListIndex = _allowListIndex;
    }

    function onDeposit(
        address sender,
        uint256 assets,
        address receiver
    ) public view virtual override returns (uint256, uint256) {
        require(sender == address(this), "MerkleTreeVerifierDepositController: Trying to bypass controller");
        return super.onDeposit(sender, assets, receiver);
    }

    function deposit(
        IFlexiblePortfolio portfolio,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public {
        require(
            verifier.verify(allowListIndex, keccak256(abi.encodePacked(msg.sender)), merkleProof),
            "MerkleTreeVerifierDepositController: Invalid proof"
        );
        portfolio.asset().safeTransferFrom(msg.sender, address(this), amount);
        portfolio.asset().approve(address(portfolio), amount);
        portfolio.deposit(amount, msg.sender);
    }

    function onMint(
        address sender,
        uint256 shares,
        address receiver
    ) public view virtual override returns (uint256, uint256) {
        require(sender == address(this), "MerkleTreeVerifierDepositController: Trying to bypass controller");
        return super.onMint(sender, shares, receiver);
    }

    function mint(
        IFlexiblePortfolio portfolio,
        uint256 shares,
        bytes32[] calldata merkleProof
    ) public {
        require(
            verifier.verify(allowListIndex, keccak256(abi.encodePacked(msg.sender)), merkleProof),
            "MerkleTreeVerifierDepositController: Invalid proof"
        );
        uint256 assets = portfolio.previewMint(shares);
        portfolio.asset().safeTransferFrom(msg.sender, address(this), assets);
        portfolio.asset().approve(address(portfolio), assets);
        portfolio.deposit(assets, msg.sender);
    }
}
