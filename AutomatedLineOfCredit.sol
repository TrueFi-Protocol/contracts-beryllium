// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {IAutomatedLineOfCredit, AutomatedLineOfCreditStatus, IERC4626} from "./interfaces/IAutomatedLineOfCredit.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IDepositStrategy} from "./interfaces/IDepositStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";

import {BasePortfolio} from "./BasePortfolio.sol";

contract AutomatedLineOfCredit is IAutomatedLineOfCredit, BasePortfolio {
    using SafeERC20 for IERC20WithDecimals;

    uint256 internal constant YEAR = 365 days;

    uint8 internal _decimals;
    uint256 public maxSize;
    uint256 public borrowedAmount;
    uint256 public accruedInterest;
    address public borrower;
    InterestRateParameters public interestRateParameters;
    uint256 private lastUtilizationUpdateTime;
    IDepositStrategy public depositStrategy;
    IWithdrawStrategy public withdrawStrategy;

    event Borrowed(uint256 amount);
    event Repaid(uint256 amount);
    event MaxSizeChanged(uint256 newMaxSize);
    event DepositStrategyChanged(IDepositStrategy indexed oldStrategy, IDepositStrategy indexed newStrategy);
    event WithdrawStrategyChanged(IWithdrawStrategy indexed oldStrategy, IWithdrawStrategy indexed newStrategy);
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
        address _transferStrategy,
        string memory name,
        string memory symbol
    ) public initializer {
        require(
            _interestRateParameters.minInterestRateUtilizationThreshold <= _interestRateParameters.optimumUtilization &&
                _interestRateParameters.optimumUtilization <= _interestRateParameters.maxInterestRateUtilizationThreshold,
            "AutomatedLineOfCredit: Min. Util. <= Optimum Util. <= Max. Util. constraint not met"
        );
        __BasePortfolio_init(_protocolConfig, _duration, _asset, _borrower, 0);
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

    function borrow(uint256 amount) public whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(address(this) != borrower, "AutomatedLineOfCredit: Pool cannot borrow from itself");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Pool end date has elapsed");
        require(amount <= virtualTokenBalance, "AutomatedLineOfCredit: Amount exceeds pool balance");

        updateAccruedInterest();
        borrowedAmount += amount;
        virtualTokenBalance -= amount;

        asset.safeTransfer(borrower, amount);

        emit Borrowed(amount);
    }

    function totalAssets() public view override(IERC4626, BasePortfolio) returns (uint256) {
        return _totalAssets(totalDebt());
    }

    function repay(uint256 amount) public whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(msg.sender != address(this), "AutomatedLineOfCredit: Pool cannot repay itself");
        require(borrower != address(this), "AutomatedLineOfCredit: Pool cannot repay itself");

        updateAccruedInterest();

        if (amount > accruedInterest) {
            uint256 repaidPrincipal = amount - accruedInterest;
            accruedInterest = 0;
            borrowedAmount -= repaidPrincipal;
        } else {
            accruedInterest -= amount;
        }

        _repay(amount);
    }

    function repayInFull() external whenNotPaused {
        require(msg.sender == borrower, "AutomatedLineOfCredit: Caller is not the borrower");
        require(msg.sender != address(this), "AutomatedLineOfCredit: Pool cannot repay itself");
        require(borrower != address(this), "AutomatedLineOfCredit: Pool cannot repay itself");
        uint256 _totalDebt = totalDebt();

        borrowedAmount = 0;
        accruedInterest = 0;
        lastUtilizationUpdateTime = 0;

        _repay(_totalDebt);
    }

    function _repay(uint256 amount) internal {
        require(amount > 0, "AutomatedLineOfCredit: Repayment amount must be greater than 0");
        virtualTokenBalance += amount;
        asset.safeTransferFrom(borrower, address(this), amount);

        emit Repaid(amount);
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return (sharesAmount * totalAssets()) / _totalSupply;
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 assets, address receiver) public override(BasePortfolio, IERC4626) whenNotPaused returns (uint256) {
        require(isDepositAllowed(msg.sender, assets), "AutomatedLineOfCredit: Deposit not allowed");
        require(receiver != address(this), "AutomatedLineOfCredit: Pool cannot be deposit receiver");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Pool end date has elapsed");
        require((totalAssets() + assets) <= maxSize, "AutomatedLineOfCredit: Deposit would cause pool to exceed max size");

        updateAccruedInterest();

        uint256 sharesToMint = convertToShares(assets);
        require(sharesToMint > 0, "AutomatedLineOfCredit: Cannot mint 0 shares");
        _mint(receiver, sharesToMint);
        virtualTokenBalance += assets;
        asset.safeTransferFrom(msg.sender, address(this), assets);

        emit Deposit(msg.sender, receiver, assets, sharesToMint);
        return sharesToMint;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenNotPaused returns (uint256) {
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot redeem to pool");
        require(owner != address(this), "AutomatedLineOfCredit: Cannot redeem from pool");
        require(shares > 0, "AutomatedLineOfCredit: Cannot redeem 0 shares");

        updateAccruedInterest();

        uint256 assetAmount = convertToAssets(shares);
        require(isWithdrawAllowed(owner, assetAmount), "AutomatedLineOfCredit: Sender not allowed to redeem");
        require(assetAmount <= virtualTokenBalance, "AutomatedLineOfCredit: Redeemed assets exceed pool balance");
        virtualTokenBalance -= assetAmount;
        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assetAmount);

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
    ) public override whenNotPaused returns (uint256) {
        uint256 shares = previewWithdraw(assets);
        require(isWithdrawAllowed(msg.sender, shares), "AutomatedLineOfCredit: Withdraw not allowed");
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot withdraw to pool");
        require(owner != address(this), "AutomatedLineOfCredit: Cannot withdraw from pool");
        require(assets > 0, "AutomatedLineOfCredit: Cannot withdraw 0 assets");
        require(assets <= virtualTokenBalance, "AutomatedLineOfCredit: Amount exceeds pool liquidity");

        updateAccruedInterest();

        virtualTokenBalance -= assets;

        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual whenNotPaused returns (uint256) {
        uint256 assets = previewMint(shares);
        require(isDepositAllowed(msg.sender, assets), "AutomatedLineOfCredit: Sender not allowed to mint");
        require(msg.sender != address(this), "AutomatedLineOfCredit: Pool cannot mint");
        require(receiver != address(this), "AutomatedLineOfCredit: Cannot mint to pool");
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Pool end date has elapsed");
        require((totalAssets() + assets) <= maxSize, "AutomatedLineOfCredit: Mint would cause pool to exceed max size");

        updateAccruedInterest();

        asset.safeTransferFrom(msg.sender, address(this), assets);
        virtualTokenBalance += assets;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
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
        return (interestRate() * borrowedAmount * (block.timestamp - lastUtilizationUpdateTime)) / YEAR / BASIS_PRECISION;
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
        uint256 maxStrategyShares = getMaxSharesFromWithdrawStrategy(owner);
        uint256 maxUserShares = min(balanceOf(owner), maxStrategyShares);
        return min(convertToAssets(maxUserShares), virtualTokenBalance);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToSharesRoundUp(assets);
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
        uint256 __totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return assets;
        } else if (__totalAssets == 0) {
            return 0;
        } else {
            return (assets * _totalSupply) / __totalAssets;
        }
    }

    function _convertToSharesRoundUp(uint256 assets) internal view returns (uint256) {
        uint256 __totalAssets = totalAssets();
        if (__totalAssets == 0) {
            return 0;
        } else {
            return Math.ceilDiv(assets * totalSupply(), __totalAssets);
        }
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        require(block.timestamp < endDate, "AutomatedLineOfCredit: Pool end date has elapsed");
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return shares;
        } else {
            return Math.ceilDiv((shares * totalAssets()), _totalSupply);
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

    function updateAccruedInterest() internal {
        accruedInterest += unincludedInterest();
        lastUtilizationUpdateTime = block.timestamp;
    }

    function isWithdrawAllowed(address receiver, uint256 amount) internal view returns (bool) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.isWithdrawAllowed(receiver, amount);
        } else {
            return true;
        }
    }

    function getMaxWithdrawFromStrategy(address owner) internal view returns (uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.maxWithdraw(owner);
        } else {
            return type(uint256).max;
        }
    }

    function isDepositAllowed(address receiver, uint256 assets) internal view returns (bool) {
        if (address(depositStrategy) != address(0x00)) {
            return depositStrategy.isDepositAllowed(receiver, assets);
        } else {
            return true;
        }
    }

    function getMaxDepositFromStrategy(address receiver) internal view returns (uint256) {
        if (address(depositStrategy) != address(0x00)) {
            return depositStrategy.maxDeposit(receiver);
        } else {
            return type(uint256).max;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _totalAssets(uint256 debt) internal view returns (uint256) {
        return virtualTokenBalance + debt;
    }

    function _utilization(uint256 debt) internal view returns (uint256) {
        if (debt == 0) {
            return 0;
        }
        return (debt * BASIS_PRECISION) / _totalAssets(debt);
    }
}
