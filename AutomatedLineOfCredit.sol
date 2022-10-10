// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAutomatedLineOfCredit, AutomatedLineOfCreditStatus} from "./interfaces/IAutomatedLineOfCredit.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IDepositStrategy} from "./interfaces/IDepositStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";
import {ITransferStrategy} from "./interfaces/ITransferStrategy.sol";

import {ERC20Upgradeable, IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {Upgradeable} from "./access/Upgradeable.sol";

contract AutomatedLineOfCredit is IAutomatedLineOfCredit, ERC20Upgradeable, Upgradeable {
    using SafeERC20 for IERC20Metadata;

    uint256 internal constant YEAR = 365 days;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGY_ADMIN_ROLE = keccak256("STRATEGY_ADMIN_ROLE");
    uint256 public constant BASIS_PRECISION = 10000;

    IERC20Metadata public asset;
    uint8 internal _decimals;
    uint256 public endDate;
    uint256 public maxSize;
    address public borrower;
    IProtocolConfig public protocolConfig;
    InterestRateParameters public interestRateParameters;

    uint256 public virtualTokenBalance;
    uint256 public borrowedAmount;
    uint256 public accruedInterest;
    uint256 public lastProtocolFeeRate;
    uint256 public unpaidFee;
    uint256 internal lastUpdateTime;

    IDepositStrategy public depositStrategy;
    IWithdrawStrategy public withdrawStrategy;
    ITransferStrategy public transferStrategy;

    event DepositStrategyChanged(IDepositStrategy indexed newStrategy);
    event WithdrawStrategyChanged(IWithdrawStrategy indexed newStrategy);
    event TransferStrategyChanged(ITransferStrategy indexed newStrategy);

    event MaxSizeChanged(uint256 newMaxSize);
    event Borrowed(uint256 amount);
    event Repaid(uint256 amount);
    event FeePaid(address indexed protocolAddress, uint256 amount);

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20Metadata _asset,
        address _borrower,
        uint256 _maxSize,
        InterestRateParameters memory _interestRateParameters,
        IDepositStrategy _depositStrategy,
        IWithdrawStrategy _withdrawStrategy,
        ITransferStrategy _transferStrategy,
        string memory name,
        string memory symbol
    ) public initializer {
        require(
            _interestRateParameters.minInterestRateUtilizationThreshold <= _interestRateParameters.optimumUtilization &&
                _interestRateParameters.optimumUtilization <= _interestRateParameters.maxInterestRateUtilizationThreshold,
            "AutomatedLineOfCredit: Min. Util. <= Optimum Util. <= Max. Util. constraint not met"
        );
        require(_duration > 0, "AutomatedLineOfCredit: Cannot have zero duration");

        __Upgradeable_init(_protocolConfig.protocolAddress(), _protocolConfig.pauserAddress());
        _grantRole(MANAGER_ROLE, _borrower);
        _grantRole(STRATEGY_ADMIN_ROLE, _borrower);
        protocolConfig = _protocolConfig;
        endDate = block.timestamp + _duration;
        asset = _asset;
        __ERC20_init(name, symbol);
        _decimals = _asset.decimals();
        borrower = _borrower;
        interestRateParameters = _interestRateParameters;
        maxSize = _maxSize;
        _setDepositStrategy(_depositStrategy);
        _setWithdrawStrategy(_withdrawStrategy);
        _setTransferStrategy(_transferStrategy);
    }

    // -- ERC20 metadata --
    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return _decimals;
    }

    // -- ERC4626 methods --
    function totalAssets() public view returns (uint256) {
        (uint256 assets, ) = getTotalAssetsAndFee();
        return assets;
    }

    function getTotalAssetsAndFee() internal view returns (uint256, uint256) {
        uint256 assetsBeforeFee = _totalAssetsBeforeAccruedFee(totalDebt());
        uint256 fee = _accruedFee(assetsBeforeFee);
        return (assetsBeforeFee - fee, fee + unpaidFee);
    }

    function _totalAssetsBeforeAccruedFee(uint256 debt) internal view returns (uint256) {
        uint256 assetsBeforeFee = virtualTokenBalance + debt;
        return unpaidFee > assetsBeforeFee ? 0 : assetsBeforeFee - unpaidFee;
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 assets, address receiver) external whenNotPaused returns (uint256) {
        (uint256 shares, ) = depositStrategy.onDeposit(msg.sender, assets, receiver);
        _executeDeposit(receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) external virtual whenNotPaused returns (uint256) {
        (uint256 assets, ) = depositStrategy.onMint(msg.sender, shares, receiver);
        _executeDeposit(receiver, assets, shares);
        return assets;
    }

    function _executeDeposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        assert(msg.sender != address(this));
        require(receiver != address(this), "AutomatedLineOfCredit: Portfolio cannot be the receiver");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        require(assets > 0 && shares > 0, "AutomatedLineOfCredit: Operation not allowed");
        (uint256 _totalAssets, uint256 fee) = getTotalAssetsAndFee();
        require(_totalAssets + assets <= maxSize, "AutomatedLineOfCredit: Operation would cause portfolio to exceed max size");

        update();
        _mint(receiver, shares);
        virtualTokenBalance += assets;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        payFee(fee);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256) {
        (uint256 shares, ) = withdrawStrategy.onWithdraw(msg.sender, assets, receiver, owner);
        _executeWithdraw(owner, receiver, assets, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256) {
        (uint256 assets, ) = withdrawStrategy.onRedeem(msg.sender, shares, receiver, owner);
        _executeWithdraw(owner, receiver, assets, shares);
        return assets;
    }

    function _executeWithdraw(
        address owner,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        assert(msg.sender != address(this));
        require(receiver != address(this), "AutomatedLineOfCredit: Portfolio cannot be the receiver");
        require(owner != address(this), "AutomatedLineOfCredit: Portfolio cannot be the owner");
        require(assets > 0 && shares > 0, "AutomatedLineOfCredit: Operation not allowed");
        (, uint256 fee) = getTotalAssetsAndFee();
        require(assets + fee <= virtualTokenBalance, "AutomatedLineOfCredit: Operation exceeds portfolio liquidity");

        update();
        _burnFrom(owner, msg.sender, shares);
        virtualTokenBalance -= assets;
        asset.safeTransfer(receiver, assets);
        payFee(fee);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        return depositStrategy.previewDeposit(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        return depositStrategy.previewMint(shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return withdrawStrategy.previewWithdraw(assets);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return withdrawStrategy.previewRedeem(shares);
    }

    function maxDeposit(address receiver) external view returns (uint256) {
        if (paused() || getStatus() != AutomatedLineOfCreditStatus.Open) {
            return 0;
        }
        if (totalAssets() >= maxSize) {
            return 0;
        }
        return depositStrategy.maxDeposit(receiver);
    }

    function maxMint(address receiver) external view returns (uint256) {
        if (paused() || getStatus() != AutomatedLineOfCreditStatus.Open) {
            return 0;
        }
        if (totalAssets() >= maxSize) {
            return 0;
        }
        return depositStrategy.maxMint(receiver);
    }

    function maxWithdraw(address owner) external view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }
        return Math.min(liquidAssets(), withdrawStrategy.maxWithdraw(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        if (paused()) {
            return 0;
        }
        return Math.min(balanceOf(owner), withdrawStrategy.maxRedeem(owner));
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return (sharesAmount * totalAssets()) / _totalSupply;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return assets;
        } else {
            uint256 _totalAssets = totalAssets();
            assert(_totalAssets != 0);
            return (assets * _totalSupply) / _totalAssets;
        }
    }

    // -- Portfolio methods --
    function borrow(uint256 assets) external whenNotPaused {
        assert(borrower != address(this));
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        require(assets > 0, "AutomatedLineOfCredit: Cannot borrow zero assets");
        (, uint256 fee) = getTotalAssetsAndFee();
        require(assets + fee <= virtualTokenBalance, "AutomatedLineOfCredit: Amount exceeds portfolio balance");

        update();
        borrowedAmount += assets;
        virtualTokenBalance -= assets;
        asset.safeTransfer(borrower, assets);
        payFee(fee);
        emit Borrowed(assets);
    }

    function repay(uint256 assets) external whenNotPaused {
        assert(borrower != address(this));
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        (, uint256 fee) = getTotalAssetsAndFee();
        update();
        require(assets <= borrowedAmount + accruedInterest, "AutomatedLineOfCredit: Amount must be less than total debt");

        if (assets > accruedInterest) {
            borrowedAmount -= (assets - accruedInterest);
            accruedInterest = 0;
        } else {
            accruedInterest -= assets;
        }
        _executeRepay(assets, fee);
    }

    function repayInFull() external whenNotPaused {
        assert(borrower != address(this));
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");

        uint256 _totalDebt = totalDebt();
        (, uint256 fee) = getTotalAssetsAndFee();
        update();
        borrowedAmount = 0;
        accruedInterest = 0;
        _executeRepay(_totalDebt, fee);
    }

    function _executeRepay(uint256 assets, uint256 fee) internal {
        require(assets > 0, "AutomatedLineOfCredit: Repayment amount must be greater than 0");
        asset.safeTransferFrom(borrower, address(this), assets);
        virtualTokenBalance += assets;
        payFee(fee);
        emit Repaid(assets);
    }

    function getStatus() public view returns (AutomatedLineOfCreditStatus) {
        if (block.timestamp >= endDate) {
            return AutomatedLineOfCreditStatus.Closed;
        } else if (totalAssets() >= maxSize) {
            return AutomatedLineOfCreditStatus.Full;
        } else {
            return AutomatedLineOfCreditStatus.Open;
        }
    }

    function utilization() public view returns (uint256) {
        if (borrowedAmount == 0) {
            return 0;
        }

        uint256 nonAccruingAssets = virtualTokenBalance + borrowedAmount;
        if (nonAccruingAssets <= unpaidFee) {
            return BASIS_PRECISION;
        }
        nonAccruingAssets -= unpaidFee;

        if (nonAccruingAssets <= borrowedAmount) {
            return BASIS_PRECISION;
        }

        return (borrowedAmount * BASIS_PRECISION) / nonAccruingAssets;
    }

    function liquidAssets() public view returns (uint256) {
        uint256 dueFee = unpaidFee + accruedFee();
        return virtualTokenBalance > dueFee ? virtualTokenBalance - dueFee : 0;
    }

    function totalDebt() public view returns (uint256) {
        return borrowedAmount + accruedInterest + unincludedInterest();
    }

    function unincludedInterest() public view returns (uint256) {
        return (interestRate() * borrowedAmount * (block.timestamp - lastUpdateTime)) / YEAR / BASIS_PRECISION;
    }

    function interestRate() public view returns (uint256) {
        uint256 currentUtilization = utilization();
        (
            uint32 minInterestRate,
            uint32 minInterestRateUtilizationThreshold,
            uint32 optimumInterestRate,
            uint32 optimumUtilization,
            uint32 maxInterestRate,
            uint32 maxInterestRateUtilizationThreshold
        ) = getInterestRateParameters();
        if (currentUtilization <= minInterestRateUtilizationThreshold) {
            return minInterestRate;
        } else if (currentUtilization <= optimumUtilization) {
            return
                solveLinear(
                    currentUtilization,
                    minInterestRateUtilizationThreshold,
                    minInterestRate,
                    optimumUtilization,
                    optimumInterestRate
                );
        } else if (currentUtilization <= maxInterestRateUtilizationThreshold) {
            return
                solveLinear(
                    currentUtilization,
                    optimumUtilization,
                    optimumInterestRate,
                    maxInterestRateUtilizationThreshold,
                    maxInterestRate
                );
        } else {
            return maxInterestRate;
        }
    }

    function updateAndPayFee() external {
        (, uint256 fee) = getTotalAssetsAndFee();
        update();
        payFee(fee);
    }

    function update() internal {
        lastProtocolFeeRate = protocolConfig.protocolFeeRate();
        accruedInterest += unincludedInterest();
        lastUpdateTime = block.timestamp;
    }

    function payFee(uint256 fee) internal {
        uint256 _virtualTokenBalance = virtualTokenBalance;
        uint256 feeToPay;
        if (_virtualTokenBalance < fee) {
            feeToPay = _virtualTokenBalance;
            unpaidFee = fee - _virtualTokenBalance;
        } else {
            feeToPay = fee;
            unpaidFee = 0;
        }
        address protocolAddress = protocolConfig.protocolAddress();
        virtualTokenBalance = _virtualTokenBalance - feeToPay;
        asset.safeTransfer(protocolAddress, feeToPay);
        emit FeePaid(protocolAddress, feeToPay);
    }

    function accruedFee() public view returns (uint256) {
        return _accruedFee(_totalAssetsBeforeAccruedFee(totalDebt()));
    }

    function _accruedFee(uint256 _totalAssets) internal view returns (uint256) {
        uint256 calculatedFee = ((block.timestamp - lastUpdateTime) * lastProtocolFeeRate * _totalAssets) / YEAR / BASIS_PRECISION;
        if (calculatedFee > _totalAssets) {
            return _totalAssets;
        } else {
            return calculatedFee;
        }
    }

    function solveLinear(
        uint256 x,
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2
    ) internal pure returns (uint256) {
        return (y1 * (x2 - x) + y2 * (x - x1)) / (x2 - x1);
    }

    function getInterestRateParameters()
        public
        view
        returns (
            uint32,
            uint32,
            uint32,
            uint32,
            uint32,
            uint32
        )
    {
        InterestRateParameters memory _interestRateParameters = interestRateParameters;
        return (
            _interestRateParameters.minInterestRate,
            _interestRateParameters.minInterestRateUtilizationThreshold,
            _interestRateParameters.optimumInterestRate,
            _interestRateParameters.optimumUtilization,
            _interestRateParameters.maxInterestRate,
            _interestRateParameters.maxInterestRateUtilizationThreshold
        );
    }

    // -- Setters --
    function setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) external onlyRole(STRATEGY_ADMIN_ROLE) {
        require(_withdrawStrategy != withdrawStrategy, "AutomatedLineOfCredit: New withdraw strategy needs to be different");
        _setWithdrawStrategy(_withdrawStrategy);
    }

    function _setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) private {
        withdrawStrategy = _withdrawStrategy;
        emit WithdrawStrategyChanged(_withdrawStrategy);
    }

    function setDepositStrategy(IDepositStrategy _depositStrategy) external onlyRole(STRATEGY_ADMIN_ROLE) {
        require(_depositStrategy != depositStrategy, "AutomatedLineOfCredit: New deposit strategy needs to be different");
        _setDepositStrategy(_depositStrategy);
    }

    function _setDepositStrategy(IDepositStrategy _depositStrategy) private {
        depositStrategy = _depositStrategy;
        emit DepositStrategyChanged(_depositStrategy);
    }

    function setTransferStrategy(ITransferStrategy _transferStrategy) external onlyRole(STRATEGY_ADMIN_ROLE) {
        require(_transferStrategy != transferStrategy, "AutomatedLineOfCredit: New transfer strategy needs to be different");
        _setTransferStrategy(_transferStrategy);
    }

    function _setTransferStrategy(ITransferStrategy _transferStrategy) internal {
        transferStrategy = _transferStrategy;
        emit TransferStrategyChanged(_transferStrategy);
    }

    function setMaxSize(uint256 _maxSize) external onlyRole(MANAGER_ROLE) {
        require(_maxSize != maxSize, "AutomatedLineOfCredit: New max size needs to be different");
        maxSize = _maxSize;
        emit MaxSizeChanged(_maxSize);
    }

    // -- EIP165 methods --
    function supportsInterface(bytes4 interfaceID) public view override(AccessControlEnumerableUpgradeable, IERC165) returns (bool) {
        return
            (interfaceID == type(IERC165).interfaceId ||
                interfaceID == type(IERC20).interfaceId ||
                interfaceID == ERC20Upgradeable.name.selector ||
                interfaceID == ERC20Upgradeable.symbol.selector ||
                interfaceID == ERC20Upgradeable.decimals.selector ||
                interfaceID == type(IERC4626).interfaceId) || super.supportsInterface(interfaceID);
    }

    // -- ERC20 methods --
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override whenNotPaused {
        super._approve(owner, spender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        require(transferStrategy.canTransfer(sender, recipient, amount), "AutomatedLineOfCredit: This transfer not permitted");
        super._transfer(sender, recipient, amount);
    }

    function _burnFrom(
        address owner,
        address spender,
        uint256 shares
    ) internal {
        if (spender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(allowed >= shares, "AutomatedLineOfCredit: Caller not approved to burn given amount of shares");
            _approve(owner, msg.sender, allowed - shares);
        }
        _burn(owner, shares);
    }
}
