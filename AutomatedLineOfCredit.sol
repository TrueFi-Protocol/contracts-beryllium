// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {IAutomatedLineOfCredit, AutomatedLineOfCreditStatus, IERC4626} from "./interfaces/IAutomatedLineOfCredit.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IDepositStrategy} from "./interfaces/IDepositStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";
import {ITransferStrategy} from "./interfaces/ITransferStrategy.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Upgradeable} from "./access/Upgradeable.sol";

contract AutomatedLineOfCredit is IAutomatedLineOfCredit, ERC20Upgradeable, Upgradeable {
    using SafeERC20 for IERC20WithDecimals;

    uint256 internal constant YEAR = 365 days;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public constant BASIS_PRECISION = 10000;

    IERC20WithDecimals public asset;
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

    event DepositStrategyChanged(IDepositStrategy indexed oldStrategy, IDepositStrategy indexed newStrategy);
    event WithdrawStrategyChanged(IWithdrawStrategy indexed oldStrategy, IWithdrawStrategy indexed newStrategy);
    event TransferStrategyChanged(ITransferStrategy indexed oldStrategy, ITransferStrategy indexed newStrategy);

    event MaxSizeChanged(uint256 newMaxSize);
    event Borrowed(uint256 amount);
    event Repaid(uint256 amount);
    event FeePaid(address indexed protocolAddress, uint256 amount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
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

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) public onlyRole(MANAGER_ROLE) {
        require(_withdrawStrategy != withdrawStrategy, "AutomatedLineOfCredit: New withdraw strategy needs to be different");
        _setWithdrawStrategy(_withdrawStrategy);
    }

    function _setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) private {
        emit WithdrawStrategyChanged(withdrawStrategy, _withdrawStrategy);
        withdrawStrategy = _withdrawStrategy;
    }

    function setDepositStrategy(IDepositStrategy _depositStrategy) public onlyRole(MANAGER_ROLE) {
        require(_depositStrategy != depositStrategy, "AutomatedLineOfCredit: New deposit strategy needs to be different");
        _setDepositStrategy(_depositStrategy);
    }

    function _setDepositStrategy(IDepositStrategy _depositStrategy) private {
        emit DepositStrategyChanged(depositStrategy, _depositStrategy);
        depositStrategy = _depositStrategy;
    }

    function setTransferStrategy(ITransferStrategy _transferStrategy) public onlyRole(MANAGER_ROLE) {
        require(_transferStrategy != transferStrategy, "AutomatedLineOfCredit: New transfer strategy needs to be different");
        _setTransferStrategy(_transferStrategy);
    }

    function _setTransferStrategy(ITransferStrategy _transferStrategy) internal {
        emit TransferStrategyChanged(transferStrategy, _transferStrategy);
        transferStrategy = _transferStrategy;
    }

    function borrow(uint256 amount) public whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(address(this) != borrower, "AutomatedLineOfCredit: Portfolio cannot borrow from itself");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        (, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        uint256 tokenBalanceAfterFee = _fee > virtualTokenBalance ? 0 : virtualTokenBalance - _fee;
        require(amount <= tokenBalanceAfterFee, "AutomatedLineOfCredit: Amount exceeds portfolio balance");
        require(amount > 0, "AutomatedLineOfCredit: Cannot borrow zero assets");

        borrowedAmount += amount;

        asset.safeTransfer(borrower, amount);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance - amount);

        updateLastProtocolFeeRate();
        emit Borrowed(amount);
    }

    function totalAssets() public view returns (uint256) {
        (uint256 assets, ) = getTotalAssetsAndFee(totalDebt());
        return assets;
    }

    function repay(uint256 amount) public whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(msg.sender != address(this), "AutomatedLineOfCredit: Portfolio cannot repay itself");
        require(borrower != address(this), "AutomatedLineOfCredit: Portfolio cannot repay itself");

        (, uint256 _fee) = updateAndGetTotalAssetsAndFee();

        if (amount > accruedInterest) {
            uint256 repaidPrincipal = amount - accruedInterest;
            accruedInterest = 0;
            borrowedAmount -= repaidPrincipal;
        } else {
            accruedInterest -= amount;
        }

        _repay(amount, _fee);
    }

    function repayInFull() external whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(msg.sender != address(this), "AutomatedLineOfCredit: Portfolio cannot repay itself");
        require(borrower != address(this), "AutomatedLineOfCredit: Portfolio cannot repay itself");

        uint256 _totalDebt = totalDebt();

        borrowedAmount = 0;
        accruedInterest = 0;
        (, uint256 feeToPay) = getTotalAssetsAndFee(_totalDebt);
        _repay(_totalDebt, feeToPay);
        lastUpdateTime = block.timestamp;
    }

    function _repay(uint256 amount, uint256 _fee) internal {
        require(amount > 0, "AutomatedLineOfCredit: Repayment amount must be greater than 0");

        asset.safeTransferFrom(borrower, address(this), amount);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance + amount);

        updateLastProtocolFeeRate();
        emit Repaid(amount);
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        return _convertToAssets(sharesAmount, totalAssets());
    }

    function _convertToAssets(uint256 sharesAmount, uint256 _totalAssets) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return (sharesAmount * _totalAssets) / _totalSupply;
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 assets, address receiver) public whenNotPaused returns (uint256) {
        require(receiver != address(this), "AutomatedLineOfCredit: Portfolio cannot be deposit receiver");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        (bool depositAllowed, ) = onDeposit(msg.sender, assets, receiver);
        require(depositAllowed, "AutomatedLineOfCredit: Deposit not allowed");

        (uint256 _totalAssets, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        uint256 sharesToMint = _convertToShares(assets, _totalAssets);
        require((_totalAssets + assets) <= maxSize, "AutomatedLineOfCredit: Deposit would cause portfolio to exceed max size");
        require(sharesToMint > 0, "AutomatedLineOfCredit: Cannot mint 0 shares");

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, sharesToMint);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance + assets);

        updateLastProtocolFeeRate();
        emit Deposit(msg.sender, receiver, assets, sharesToMint);
        return sharesToMint;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public whenNotPaused returns (uint256) {
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot redeem to portfolio");
        require(owner != address(this), "AutomatedLineOfCredit: Cannot redeem from portfolio");
        require(shares > 0, "AutomatedLineOfCredit: Cannot redeem 0 shares");

        (uint256 _totalAssets, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        uint256 assetAmount = _convertToAssets(shares, _totalAssets);
        uint256 tokenBalanceAfterFee = _fee > virtualTokenBalance ? 0 : virtualTokenBalance - _fee;
        require(assetAmount <= tokenBalanceAfterFee, "AutomatedLineOfCredit: Redeemed assets exceed portfolio balance");
        (bool withdrawAllowed, ) = onRedeem(msg.sender, assetAmount, receiver, owner);
        require(withdrawAllowed, "AutomatedLineOfCredit: Redeem not allowed");

        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assetAmount);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance - assetAmount);

        updateLastProtocolFeeRate();
        emit Withdraw(msg.sender, receiver, owner, assetAmount, shares);

        return assetAmount;
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

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public whenNotPaused returns (uint256) {
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot withdraw to portfolio");
        require(owner != address(this), "AutomatedLineOfCredit: Cannot withdraw from portfolio");
        require(assets > 0, "AutomatedLineOfCredit: Cannot withdraw 0 assets");

        (uint256 _totalAssets, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        uint256 shares = _previewWithdraw(assets, _totalAssets);
        uint256 tokenBalanceAfterFee = _fee > virtualTokenBalance ? 0 : virtualTokenBalance - _fee;
        require(assets <= tokenBalanceAfterFee, "AutomatedLineOfCredit: Amount exceeds portfolio liquidity");
        (bool withdrawAllowed, ) = onWithdraw(msg.sender, assets, receiver, owner);
        require(withdrawAllowed, "AutomatedLineOfCredit: Withdraw not allowed");

        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assets);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance - assets);

        updateLastProtocolFeeRate();
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual whenNotPaused returns (uint256) {
        require(msg.sender != address(this), "AutomatedLineOfCredit: Portfolio cannot mint");
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot mint to portfolio");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");

        (uint256 _totalAssets, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        uint256 assets = _previewMint(shares, _totalAssets);
        (bool depositAllowed, ) = onDeposit(msg.sender, assets, receiver);
        require(depositAllowed, "AutomatedLineOfCredit: Sender not allowed to mint");
        require((_totalAssets + assets) <= maxSize, "AutomatedLineOfCredit: Mint would cause portfolio to exceed max size");

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance + assets);

        updateLastProtocolFeeRate();
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function payFeeAndUpdateVirtualTokenBalance(uint256 _fee, uint256 totalBalance) internal {
        uint256 _feePaid = payFee(_fee, totalBalance);
        virtualTokenBalance = totalBalance - _feePaid;
    }

    function payFee(uint256 _fee, uint256 balance) internal returns (uint256) {
        uint256 feeToPay;
        if (balance < _fee) {
            feeToPay = balance;
            unpaidFee = _fee - balance;
        } else {
            feeToPay = _fee;
            unpaidFee = 0;
        }
        address protocolAddress = protocolConfig.protocolAddress();
        asset.safeTransfer(protocolAddress, feeToPay);
        emit FeePaid(protocolAddress, feeToPay);
        return feeToPay;
    }

    function updateAndPayFee() public {
        (, uint256 _fee) = updateAndGetTotalAssetsAndFee();
        payFeeAndUpdateVirtualTokenBalance(_fee, virtualTokenBalance);
        updateLastProtocolFeeRate();
    }

    function updateAndGetTotalAssetsAndFee() internal returns (uint256, uint256) {
        accruedInterest += unincludedInterest();
        (uint256 _totalAssets, uint256 fee) = getTotalAssetsAndFee(borrowedAmount + accruedInterest);
        lastUpdateTime = block.timestamp;
        return (_totalAssets, fee);
    }

    function getMaxSharesFromWithdrawStrategy(address owner) internal view returns (uint256) {
        uint256 maxAssetsAllowed = getMaxWithdrawFromStrategy(owner);
        if (maxAssetsAllowed == type(uint256).max) {
            return type(uint256).max;
        } else {
            return convertToShares(maxAssetsAllowed);
        }
    }

    function maxRedeem(address owner) public view returns (uint256) {
        if (paused()) {
            return 0;
        }
        uint256 maxVirtualShares = convertToShares(virtualTokenBalance);
        uint256 maxStrategyShares = getMaxSharesFromWithdrawStrategy(owner);
        return min(min(balanceOf(owner), maxStrategyShares), maxVirtualShares);
    }

    function unincludedInterest() public view returns (uint256) {
        return (interestRate() * borrowedAmount * (block.timestamp - lastUpdateTime)) / YEAR / BASIS_PRECISION;
    }

    function interestRate() public view returns (uint256) {
        return _interestRate(_utilization(borrowedAmount));
    }

    function _interestRate(uint256 currentUtilization) internal view returns (uint256) {
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

    function maxDeposit(address receiver) public view returns (uint256) {
        if (paused() || getStatus() != AutomatedLineOfCreditStatus.Open) {
            return 0;
        } else {
            return min(maxSize - totalAssets(), getMaxDepositFromStrategy(receiver));
        }
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }
        uint256 maxStrategyWithdraw = getMaxWithdrawFromStrategy(owner);
        uint256 maxUserWithdraw = min(convertToAssets(balanceOf(owner)), maxStrategyWithdraw);
        return min(maxUserWithdraw, virtualTokenBalance);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return _previewWithdraw(assets, _totalAssets);
    }

    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256) {
        if (_totalAssets == 0) {
            return 0;
        } else {
            return Math.ceilDiv(assets * totalSupply(), _totalAssets);
        }
    }

    function setMaxSize(uint256 _maxSize) external onlyRole(MANAGER_ROLE) {
        require(_maxSize != maxSize, "AutomatedLineOfCredit: New max size needs to be different");
        maxSize = _maxSize;
        emit MaxSizeChanged(_maxSize);
    }

    function utilization() external view returns (uint256) {
        return _utilization(borrowedAmount);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    function _convertToShares(uint256 assets, uint256 _totalAssets) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return assets;
        } else if (_totalAssets == 0) {
            return 0;
        } else {
            return (assets * _totalSupply) / _totalAssets;
        }
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Portfolio end date has elapsed");
        return _previewMint(shares, totalAssets());
    }

    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return shares;
        } else {
            return Math.ceilDiv((shares * _totalAssets), _totalSupply);
        }
    }

    function maxMint(address receiver) public view returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function totalDebt() public view returns (uint256) {
        return borrowedAmount + accruedInterest + unincludedInterest();
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

    function getStatus() public view returns (AutomatedLineOfCreditStatus) {
        if (block.timestamp >= endDate) {
            return AutomatedLineOfCreditStatus.Closed;
        } else if (totalAssets() >= maxSize) {
            return AutomatedLineOfCreditStatus.Full;
        } else {
            return AutomatedLineOfCreditStatus.Open;
        }
    }

    function updateLastProtocolFeeRate() internal {
        lastProtocolFeeRate = protocolConfig.protocolFeeRate();
    }

    function onWithdraw(
        address sender,
        uint256 amount,
        address receiver,
        address owner
    ) internal returns (bool, uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.onWithdraw(sender, amount, receiver, owner);
        } else {
            return (true, 0);
        }
    }

    function onRedeem(
        address sender,
        uint256 amount,
        address receiver,
        address owner
    ) internal returns (bool, uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.onRedeem(sender, amount, receiver, owner);
        } else {
            return (true, 0);
        }
    }

    function getMaxWithdrawFromStrategy(address owner) internal view returns (uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.maxWithdraw(owner);
        } else {
            return type(uint256).max;
        }
    }

    function onDeposit(
        address sender,
        uint256 assets,
        address receiver
    ) internal returns (bool, uint256) {
        if (address(depositStrategy) != address(0x00)) {
            return depositStrategy.onDeposit(sender, assets, receiver);
        } else {
            return (true, 0);
        }
    }

    function getMaxDepositFromStrategy(address receiver) internal view returns (uint256) {
        if (address(depositStrategy) != address(0x00)) {
            return depositStrategy.maxDeposit(receiver);
        } else {
            return type(uint256).max;
        }
    }

    function accruedFee() external view returns (uint256) {
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _totalAssetsBeforeAccruedFee(uint256 debt) internal view returns (uint256) {
        uint256 assetsBeforeFee = virtualTokenBalance + debt;
        return unpaidFee > assetsBeforeFee ? 0 : assetsBeforeFee - unpaidFee;
    }

    function getTotalAssetsAndFee(uint256 debt) internal view returns (uint256, uint256) {
        uint256 assetsBeforeFee = _totalAssetsBeforeAccruedFee(debt);
        uint256 fee = _accruedFee(assetsBeforeFee);
        if (fee > assetsBeforeFee) {
            return (0, fee + unpaidFee);
        } else {
            return (assetsBeforeFee - fee, fee + unpaidFee);
        }
    }

    function _utilization(uint256 debt) internal view returns (uint256) {
        if (debt == 0) {
            return 0;
        }
        return (debt * BASIS_PRECISION) / _totalAssetsBeforeAccruedFee(debt);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        if (address(transferStrategy) != address(0)) {
            require(transferStrategy.canTransfer(sender, recipient, amount), "AutomatedLineOfCredit: This transfer not permitted");
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
