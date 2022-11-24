// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDepositController} from "../interfaces/IDepositController.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMerkleTreeVerifier} from "../lithium/interfaces/IMerkleTreeVerifier.sol";
import {IPortfolio} from "../interfaces/IPortfolio.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract MerkleTreeVerifierDepositController is IDepositController, Initializable {
    using SafeERC20 for IERC20Metadata;

    event LenderVerifierChanged(IMerkleTreeVerifier indexed newLenderVerifier);

    address public manager;
    IMerkleTreeVerifier public lenderVerifier;
    uint256 public allowListIndex;

    function initialize(
        address _manager,
        IMerkleTreeVerifier _lenderVerifier,
        uint256 _allowListIndex
    ) external initializer {
        lenderVerifier = _lenderVerifier;
        allowListIndex = _allowListIndex;
        manager = _manager;
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return IPortfolio(msg.sender).maxSize() - IPortfolio(msg.sender).totalAssets();
    }

    function maxMint(address receiver) public view virtual returns (uint256) {
        return previewDeposit(maxDeposit(receiver));
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

    function onDeposit(
        address sender,
        uint256 assets,
        address
    ) public view virtual override returns (uint256, uint256) {
        require(sender == address(this), "MerkleTreeVerifierDepositController: Trying to bypass controller");
        return (previewDeposit(assets), 0);
    }

    function onMint(
        address sender,
        uint256 shares,
        address
    ) public view virtual override returns (uint256, uint256) {
        require(sender == address(this), "MerkleTreeVerifierDepositController: Trying to bypass controller");
        return (previewMint(shares), 0);
    }

    function deposit(
        IPortfolio portfolio,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public {
        require(
            lenderVerifier.verify(allowListIndex, keccak256(abi.encodePacked(msg.sender)), merkleProof),
            "MerkleTreeVerifierDepositController: Invalid proof"
        );
        portfolio.asset().safeTransferFrom(msg.sender, address(this), amount);
        portfolio.asset().approve(address(portfolio), amount);
        portfolio.deposit(amount, msg.sender);
    }

    function mint(
        IPortfolio portfolio,
        uint256 shares,
        bytes32[] calldata merkleProof
    ) public {
        require(
            lenderVerifier.verify(allowListIndex, keccak256(abi.encodePacked(msg.sender)), merkleProof),
            "MerkleTreeVerifierDepositController: Invalid proof"
        );
        uint256 assets = portfolio.previewMint(shares);
        portfolio.asset().safeTransferFrom(msg.sender, address(this), assets);
        portfolio.asset().approve(address(portfolio), assets);
        portfolio.deposit(assets, msg.sender);
    }

    function setLenderVerifier(IMerkleTreeVerifier _lenderVerifier) public {
        require(msg.sender == manager, "MerkleTreeVerifierDepositController: sender is not manager");
        _setLenderVerifier(_lenderVerifier);
    }

    function _setLenderVerifier(IMerkleTreeVerifier _lenderVerifier) internal {
        lenderVerifier = _lenderVerifier;
        emit LenderVerifierChanged(_lenderVerifier);
    }
}
