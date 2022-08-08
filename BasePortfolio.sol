// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Upgradeable} from "./access/Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IBasePortfolio} from "./interfaces/IBasePortfolio.sol";
import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {ITransferStrategy} from "./interfaces/ITransferStrategy.sol";

abstract contract BasePortfolio is IBasePortfolio, ERC20Upgradeable, Upgradeable {
    using SafeERC20 for IERC20WithDecimals;

    event Deposited(uint256 shares, uint256 amount, address indexed sender);
    event Withdrawn(uint256 shares, uint256 amount, address indexed sender);
    event TransferStrategyChanged(address indexed oldStrategy, address indexed newStrategy);
    event FeePaid(address indexed sender, address indexed recipient, uint256 amount);

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    uint256 public constant BASIS_PRECISION = 10000;

    uint256 public endDate;
    IERC20WithDecimals public asset;
    uint8 public assetDecimals;

    address public transferStrategy;
    IProtocolConfig public protocolConfig;
    uint256 public managerFee;
    uint256 public virtualTokenBalance;

    function __BasePortfolio_init(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
        address _manager,
        uint256 _managerFee
    ) internal initializer {
        require(_duration > 0, "BasePortfolio: Cannot have zero duration");
        __Upgradeable_init(_protocolConfig.protocolAddress(), _protocolConfig.pauserAddress());
        _grantRole(MANAGER_ROLE, _manager);
        _setRoleAdmin(DEPOSIT_ROLE, MANAGER_ROLE);
        _setRoleAdmin(WITHDRAW_ROLE, MANAGER_ROLE);

        protocolConfig = _protocolConfig;
        endDate = block.timestamp + _duration;
        asset = _asset;
        assetDecimals = IERC20WithDecimals(address(_asset)).decimals();
        if (_managerFee > 0) {
            managerFee = _managerFee;
        }
    }

    function setTransferStrategy(address _transferStrategy) public onlyRole(MANAGER_ROLE) {
        _setTransferStrategy(_transferStrategy);
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 amount, address sender) public virtual whenNotPaused returns (uint256) {
        uint256 sharesToMint = calculateSharesToMint(amount);
        _mint(sender, sharesToMint);
        virtualTokenBalance += amount;
        asset.safeTransferFrom(sender, address(this), amount);
        emit Deposited(sharesToMint, amount, sender);
        return sharesToMint;
    }

    function withdraw(uint256 shares, address sender) public virtual whenNotPaused {
        uint256 amountToWithdraw = calculateAmountToWithdraw(shares);
        require(amountToWithdraw <= virtualTokenBalance, "BasePortfolio: Amount exceeds pool balance");
        virtualTokenBalance -= amountToWithdraw;
        _burn(sender, shares);
        asset.safeTransfer(sender, amountToWithdraw);
        emit Withdrawn(shares, amountToWithdraw, sender);
    }

    function calculateSharesToMint(uint256 depositedAmount) public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return (depositedAmount * 10**decimals()) / (10**assetDecimals);
        } else {
            return (depositedAmount * _totalSupply) / totalAssets();
        }
    }

    function calculateAmountToWithdraw(uint256 shares) public view virtual returns (uint256) {
        return (shares * totalAssets()) / totalSupply();
    }

    function totalAssets() public view virtual returns (uint256) {
        return virtualTokenBalance;
    }

    function _setTransferStrategy(address _transferStrategy) internal {
        address oldTransferStrategy = transferStrategy;
        require(_transferStrategy != oldTransferStrategy, "BasePortfolio: New transfer strategy needs to be different");

        transferStrategy = _transferStrategy;
        emit TransferStrategyChanged(oldTransferStrategy, _transferStrategy);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        if (transferStrategy != address(0)) {
            require(
                ITransferStrategy(transferStrategy).canTransfer(sender, recipient, amount),
                "BasePortfolio: This transfer not permitted"
            );
        }
        super._transfer(sender, recipient, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override whenNotPaused {
        super._approve(owner, spender, amount);
    }
}
