// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IValuationStrategy} from "./interfaces/IValuationStrategy.sol";
import {ITransferStrategy} from "./interfaces/ITransferStrategy.sol";
import {IDepositStrategy} from "./interfaces/IDepositStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";
import {IFeeStrategy} from "./interfaces/IFeeStrategy.sol";
import {Upgradeable} from "./access/Upgradeable.sol";

contract FlexiblePortfolio is IFlexiblePortfolio, ERC20Upgradeable, Upgradeable {
    using SafeERC20 for IERC20WithDecimals;
    using Address for address;

    uint256 internal constant YEAR = 365 days;
    uint256 public constant BASIS_PRECISION = 10000;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IERC20WithDecimals public asset;
    uint8 internal _decimals;
    uint256 public endDate;
    uint256 public maxSize;
    IProtocolConfig public protocolConfig;
    mapping(IDebtInstrument => bool) public isInstrumentAllowed;

    uint256 public virtualTokenBalance;
    uint256 public lastProtocolFee;
    uint256 public lastManagerFee;
    uint256 public unpaidProtocolFee;
    uint256 public unpaidManagerFee;
    uint256 internal lastUpdateTime;

    IValuationStrategy public valuationStrategy;
    IDepositStrategy public depositStrategy;
    IWithdrawStrategy public withdrawStrategy;
    ITransferStrategy public transferStrategy;
    IFeeStrategy public feeStrategy;

    mapping(IDebtInstrument => mapping(uint256 => bool)) public isInstrumentAdded;

    event InstrumentAdded(IDebtInstrument indexed instrument, uint256 indexed instrumentId);
    event InstrumentFunded(IDebtInstrument indexed instrument, uint256 indexed instrumentId);
    event InstrumentUpdated(IDebtInstrument indexed instrument);
    event AllowedInstrumentChanged(IDebtInstrument indexed instrument, bool isAllowed);
    event InstrumentRepaid(IDebtInstrument indexed instrument, uint256 indexed instrumentId, uint256 amount);

    event MaxSizeChanged(uint256 newMaxSize);
    event ValuationStrategyChanged(IValuationStrategy indexed strategy);
    event DepositStrategyChanged(IDepositStrategy indexed oldStrategy, IDepositStrategy indexed newStrategy);
    event WithdrawStrategyChanged(IWithdrawStrategy indexed oldStrategy, IWithdrawStrategy indexed newStrategy);
    event TransferStrategyChanged(ITransferStrategy indexed oldStrategy, ITransferStrategy indexed newStrategy);
    event FeeStrategyChanged(IFeeStrategy indexed oldStrategy, IFeeStrategy indexed newStrategy);

    event FeePaid(address indexed protocolAddress, uint256 amount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
        address _manager,
        uint256 _maxSize,
        Strategies calldata _strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        ERC20Metadata calldata tokenMetadata
    ) external initializer {
        require(_duration > 0, "FlexiblePortfolio: Cannot have zero duration");
        __Upgradeable_init(_protocolConfig.protocolAddress(), _protocolConfig.pauserAddress());
        __ERC20_init(tokenMetadata.name, tokenMetadata.symbol);
        _grantRole(MANAGER_ROLE, _manager);
        protocolConfig = _protocolConfig;
        endDate = block.timestamp + _duration;
        asset = _asset;
        maxSize = _maxSize;
        _decimals = _asset.decimals();
        _setDepositStrategy(_strategies.depositStrategy);
        _setWithdrawStrategy(_strategies.withdrawStrategy);
        _setTransferStrategy(_strategies.transferStrategy);
        _setFeeStrategy(_strategies.feeStrategy);
        valuationStrategy = _strategies.valuationStrategy;

        for (uint256 i; i < _allowedInstruments.length; i++) {
            isInstrumentAllowed[_allowedInstruments[i]] = true;
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) public onlyRole(MANAGER_ROLE) {
        require(_withdrawStrategy != withdrawStrategy, "FlexiblePortfolio: New withdraw strategy needs to be different");
        _setWithdrawStrategy(_withdrawStrategy);
    }

    function _setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) private {
        emit WithdrawStrategyChanged(withdrawStrategy, _withdrawStrategy);
        withdrawStrategy = _withdrawStrategy;
    }

    function setDepositStrategy(IDepositStrategy _depositStrategy) public onlyRole(MANAGER_ROLE) {
        require(_depositStrategy != depositStrategy, "FlexiblePortfolio: New deposit strategy needs to be different");
        _setDepositStrategy(_depositStrategy);
    }

    function _setDepositStrategy(IDepositStrategy _depositStrategy) private {
        emit DepositStrategyChanged(depositStrategy, _depositStrategy);
        depositStrategy = _depositStrategy;
    }

    function allowInstrument(IDebtInstrument instrument, bool isAllowed) external onlyRole(MANAGER_ROLE) {
        isInstrumentAllowed[instrument] = isAllowed;
        emit AllowedInstrumentChanged(instrument, isAllowed);
    }

    function addInstrument(IDebtInstrument instrument, bytes calldata issueInstrumentCalldata)
        external
        onlyRole(MANAGER_ROLE)
        returns (uint256)
    {
        require(isInstrumentAllowed[instrument], "FlexiblePortfolio: Instrument is not allowed");
        require(instrument.issueInstrumentSelector() == bytes4(issueInstrumentCalldata), "FlexiblePortfolio: Invalid function call");

        bytes memory result = address(instrument).functionCall(issueInstrumentCalldata);

        uint256 instrumentId = abi.decode(result, (uint256));
        require(instrument.asset(instrumentId) == asset, "FlexiblePortfolio: Cannot add instrument with different underlying token");
        isInstrumentAdded[instrument][instrumentId] = true;
        emit InstrumentAdded(instrument, instrumentId);

        return instrumentId;
    }

    function fundInstrument(IDebtInstrument instrument, uint256 instrumentId) public onlyRole(MANAGER_ROLE) {
        require(isInstrumentAdded[instrument][instrumentId], "FlexiblePortfolio: Instrument is not added");
        address borrower = instrument.recipient(instrumentId);
        uint256 principalAmount = instrument.principal(instrumentId);
        (, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 totalFee = protocolFee + managerFee;
        require(totalFee + principalAmount <= virtualTokenBalance, "FlexiblePortfolio: Insufficient funds in portfolio to fund loan");
        instrument.start(instrumentId);
        require(
            instrument.endDate(instrumentId) <= endDate,
            "FlexiblePortfolio: Cannot fund instrument which end date is after portfolio end date"
        );
        valuationStrategy.onInstrumentFunded(this, instrument, instrumentId);
        asset.safeTransfer(borrower, principalAmount);
        _payFeeAndUpdate(protocolFee, managerFee, 0, virtualTokenBalance - principalAmount);
        emit InstrumentFunded(instrument, instrumentId);
    }

    function updateInstrument(IDebtInstrument instrument, bytes calldata updateInstrumentCalldata) external onlyRole(MANAGER_ROLE) {
        require(isInstrumentAllowed[instrument], "FlexiblePortfolio: Instrument is not allowed");
        require(instrument.updateInstrumentSelector() == bytes4(updateInstrumentCalldata), "FlexiblePortfolio: Invalid function call");

        address(instrument).functionCall(updateInstrumentCalldata);
        emit InstrumentUpdated(instrument);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");
        uint256 fee = address(depositStrategy) != address(0x00) ? depositStrategy.previewDepositFee(assets) : 0;
        uint256 assetsAfterFee = assets > fee ? assets - fee : 0;
        return convertToShares(assetsAfterFee);
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        (bool depositAllowed, uint256 depositFee) = onDeposit(msg.sender, assets, receiver);
        require(depositAllowed, "FlexiblePortfolio: Deposit not allowed");
        require(assets >= depositFee, "FlexiblePortfolio: Fee cannot be bigger than deposited assets");
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 assetsAfterDepositFee = assets - depositFee;
        require(assetsAfterDepositFee + _totalAssets <= maxSize, "FlexiblePortfolio: Deposit would cause pool to exceed max size");
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");
        require(receiver != address(this), "FlexiblePortfolio: Portfolio cannot be deposit receiver");

        uint256 sharesToMint = _convertToShares(assetsAfterDepositFee, _totalAssets);
        require(sharesToMint > 0, "FlexiblePortfolio: Cannot mint 0 shares");

        _mint(receiver, sharesToMint);
        asset.safeTransferFrom(msg.sender, address(this), assetsAfterDepositFee);
        _payFeeAndUpdate(protocolFee, managerFee, depositFee, virtualTokenBalance + assets);

        emit Deposit(msg.sender, receiver, assetsAfterDepositFee, sharesToMint);
        return sharesToMint;
    }

    function mint(uint256 shares, address receiver) public whenNotPaused returns (uint256) {
        require(receiver != address(this), "FlexiblePortfolio: Portfolio cannot be mint receiver");
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 assets = _previewMint(shares, _totalAssets);
        (bool depositAllowed, uint256 mintFee) = onMint(msg.sender, assets, receiver);
        uint256 assetsWithMintFee = assets + mintFee;
        require(depositAllowed, "FlexiblePortfolio: Sender not allowed to mint");
        require(assets + _totalAssets <= maxSize, "FlexiblePortfolio: Portfolio is full");
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");

        _mint(receiver, shares);
        asset.safeTransferFrom(msg.sender, address(this), assetsWithMintFee);
        _payFeeAndUpdate(protocolFee, managerFee, mintFee, virtualTokenBalance + assetsWithMintFee);

        emit Deposit(msg.sender, receiver, assets, shares);
        return assetsWithMintFee + protocolFee + managerFee;
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 assets = _previewMint(shares, totalAssets());
        uint256 fee = address(depositStrategy) != address(0x00) ? depositStrategy.previewMintFee(assets) : 0;
        return assets + fee;
    }

    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return shares;
        }
        return Math.ceilDiv(shares * _totalAssets, _totalSupply);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual whenNotPaused returns (uint256) {
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 assets = _convertToAssets(shares, _totalAssets);
        (bool withdrawAllowed, uint256 redeemFee) = onRedeem(msg.sender, assets, receiver, owner);
        require(assets >= redeemFee, "FlexiblePortfolio: Redeem fee is bigger than redeemed assets");
        require(withdrawAllowed, "FlexiblePortfolio: Withdraw not allowed");
        require(assets + protocolFee + managerFee <= virtualTokenBalance, "FlexiblePortfolio: Amount exceeds portfolio balance");

        _burnFrom(owner, msg.sender, shares);
        uint256 assetsAfterRedeemFee = assets - redeemFee;
        asset.safeTransfer(receiver, assetsAfterRedeemFee);
        _payFeeAndUpdate(protocolFee, managerFee, redeemFee, virtualTokenBalance - assetsAfterRedeemFee);

        emit Withdraw(msg.sender, receiver, owner, assetsAfterRedeemFee, shares);
        return assetsAfterRedeemFee;
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

    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(recipient, amount);
    }

    function repay(
        IDebtInstrument instrument,
        uint256 instrumentId,
        uint256 amount
    ) external whenNotPaused {
        require(amount > 0, "FlexiblePortfolio: Repayment amount must be greater than 0");
        require(instrument.recipient(instrumentId) == msg.sender, "FlexiblePortfolio: Not an instrument recipient");
        (, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        instrument.repay(instrumentId, amount);
        valuationStrategy.onInstrumentUpdated(this, instrument, instrumentId);

        instrument.asset(instrumentId).safeTransferFrom(msg.sender, address(this), amount);
        _payFeeAndUpdate(protocolFee, managerFee, 0, virtualTokenBalance + amount);
        emit InstrumentRepaid(instrument, instrumentId, amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function payFeeAndUpdate() external {
        (, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        _payFeeAndUpdate(protocolFee, managerFee, 0, virtualTokenBalance);
    }

    function _payFeeAndUpdate(
        uint256 protocolFee,
        uint256 managerContinuousFee,
        uint256 managerActionFee,
        uint256 totalBalance
    ) internal {
        totalBalance -= managerActionFee;
        uint256 protocolFeePaid = payProtocolFee(protocolFee, totalBalance);
        uint256 managerFeePaid = payManagerFee(managerContinuousFee, managerActionFee, totalBalance - protocolFeePaid);
        virtualTokenBalance = totalBalance - protocolFeePaid - managerFeePaid;
        lastUpdateTime = block.timestamp;
        updateLastProtocolFee();
        updateLastManagerFee();
    }

    function payManagerFee(
        uint256 continuousFee,
        uint256 actionFee,
        uint256 liquidity
    ) internal returns (uint256) {
        uint256 continuousFeeToPay;
        if (liquidity < continuousFee) {
            continuousFeeToPay = liquidity;
            unpaidManagerFee = continuousFee - liquidity;
        } else {
            continuousFeeToPay = continuousFee;
            unpaidManagerFee = 0;
        }
        payFee(managerFeeBeneficiary(), continuousFeeToPay + actionFee);
        return continuousFeeToPay;
    }

    function payProtocolFee(uint256 _fee, uint256 balance) internal returns (uint256) {
        uint256 feeToPay;
        if (balance < _fee) {
            feeToPay = balance;
            unpaidProtocolFee = _fee - balance;
        } else {
            feeToPay = _fee;
            unpaidProtocolFee = 0;
        }
        payFee(protocolConfig.protocolAddress(), feeToPay);
        return feeToPay;
    }

    function payFee(address feeReceiver, uint256 _fee) internal {
        asset.safeTransfer(feeReceiver, _fee);
        emit FeePaid(feeReceiver, _fee);
    }

    function setValuationStrategy(IValuationStrategy _valuationStrategy) external onlyRole(MANAGER_ROLE) {
        require(_valuationStrategy != valuationStrategy, "FlexiblePortfolio: New valuation strategy needs to be different");
        valuationStrategy = _valuationStrategy;
        emit ValuationStrategyChanged(_valuationStrategy);
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        return _convertToAssets(sharesAmount, totalAssets());
    }

    function _convertToAssets(uint256 sharesAmount, uint256 _totalAssets) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return (sharesAmount * _totalAssets) / _totalSupply;
    }

    function totalAssetsBeforeAccruedFee() internal view returns (uint256) {
        if (address(valuationStrategy) == address(0)) {
            return 0;
        }
        uint256 _totalAssets = virtualTokenBalance + valuationStrategy.calculateValue(this);
        return unpaidProtocolFee > _totalAssets ? 0 : _totalAssets - unpaidProtocolFee;
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 _totalAssets, , ) = getTotalAssetsAndFee();
        return _totalAssets;
    }

    function getTotalAssetsAndFee()
        internal
        view
        returns (
            uint256 totalAssetsAfterFee,
            uint256 protocolFee,
            uint256 managerFee
        )
    {
        uint256 assetsBeforeFee = totalAssetsBeforeAccruedFee();
        (uint256 accruedProtocolFee, uint256 accruedManagerFee) = _accruedFee(assetsBeforeFee);
        return (assetsBeforeFee - accruedProtocolFee - accruedManagerFee, accruedProtocolFee + unpaidProtocolFee, accruedManagerFee);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return assets;
        } else if (_totalAssets == 0) {
            return 0;
        } else {
            return (assets * _totalSupply) / _totalAssets;
        }
    }

    function maxMint(address receiver) public view returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 fee = address(withdrawStrategy) != address(0x00) ? withdrawStrategy.previewRedeemFee(shares) : 0;
        uint256 assets = convertToAssets(shares);
        return fee < assets ? assets - fee : 0;
    }

    function liquidValue() public view returns (uint256) {
        return virtualTokenBalance;
    }

    function maxDeposit(address receiver) public view returns (uint256) {
        if (paused() || block.timestamp >= endDate) {
            return 0;
        }
        uint256 _totalAssets = totalAssets();
        if (_totalAssets >= maxSize) {
            return 0;
        } else {
            return min(maxSize - _totalAssets, getMaxDepositFromStrategy(receiver));
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

    function setMaxSize(uint256 _maxSize) external onlyRole(MANAGER_ROLE) {
        require(_maxSize != maxSize, "FlexiblePortfolio: New max size needs to be different");
        maxSize = _maxSize;
        emit MaxSizeChanged(_maxSize);
    }

    function cancelInstrument(IDebtInstrument instrument, uint256 instrumentId) external onlyRole(MANAGER_ROLE) {
        instrument.cancel(instrumentId);
        valuationStrategy.onInstrumentUpdated(this, instrument, instrumentId);
    }

    function markInstrumentAsDefaulted(IDebtInstrument instrument, uint256 instrumentId) external onlyRole(MANAGER_ROLE) {
        instrument.markAsDefaulted(instrumentId);
        valuationStrategy.onInstrumentUpdated(this, instrument, instrumentId);
    }

    function getMaxWithdrawFromStrategy(address owner) internal view returns (uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.maxWithdraw(owner);
        } else {
            return type(uint256).max;
        }
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

    function onMint(
        address sender,
        uint256 assets,
        address receiver
    ) internal returns (bool, uint256) {
        if (address(depositStrategy) != address(0x00)) {
            return depositStrategy.onMint(sender, assets, receiver);
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _burnFrom(
        address owner,
        address spender,
        uint256 shares
    ) internal {
        if (spender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(allowed >= shares, "FlexiblePortfolio: Caller not approved to burn given amount of shares");
            _approve(owner, msg.sender, allowed - shares);
        }
        _burn(owner, shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 fee = address(withdrawStrategy) != address(0x00) ? withdrawStrategy.previewWithdrawFee(assets) : 0;
        return _previewWithdraw(assets + fee, totalAssets());
    }

    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256) {
        if (_totalAssets == 0) {
            return 0;
        } else {
            return Math.ceilDiv(assets * totalSupply(), _totalAssets);
        }
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public whenNotPaused returns (uint256) {
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        (bool withdrawAllowed, uint256 withdrawFee) = onWithdraw(msg.sender, assets, receiver, owner);
        uint256 shares = _previewWithdraw(assets + withdrawFee, _totalAssets);
        require(withdrawAllowed, "FlexiblePortfolio: Withdraw not allowed");
        require(receiver != address(this), "FlexiblePortfolio: Cannot withdraw to pool");
        require(owner != address(this), "FlexiblePortfolio: Cannot withdraw from pool");
        require(assets > 0, "FlexiblePortfolio: Cannot withdraw 0 assets");
        require(
            assets + withdrawFee + protocolFee + managerFee <= virtualTokenBalance,
            "FlexiblePortfolio: Amount exceeds pool balance"
        );
        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assets);
        _payFeeAndUpdate(protocolFee, managerFee, withdrawFee, virtualTokenBalance - assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function updateLastProtocolFee() internal {
        lastProtocolFee = protocolConfig.protocolFee();
    }

    function updateLastManagerFee() internal {
        if (address(feeStrategy) != address(0x00)) {
            lastManagerFee = feeStrategy.managerFee();
        } else {
            lastManagerFee = 0;
        }
    }

    function accruedFee() external view returns (uint256 accruedProtocolFee, uint256 accruedManagerFee) {
        return _accruedFee(totalAssetsBeforeAccruedFee());
    }

    function _accruedFee(uint256 _totalAssets) internal view returns (uint256 accruedProtocolFee, uint256 accruedManagerFee) {
        uint256 adjustedTotalAssets = (block.timestamp - lastUpdateTime) * _totalAssets;
        uint256 calculatedProtocolFee = (adjustedTotalAssets * lastProtocolFee) / YEAR / BASIS_PRECISION;
        if (calculatedProtocolFee > _totalAssets) {
            return (_totalAssets, 0);
        }
        uint256 calculatedManagerFee = (adjustedTotalAssets * lastManagerFee) / YEAR / BASIS_PRECISION;
        if (calculatedProtocolFee + calculatedManagerFee > _totalAssets) {
            return (calculatedProtocolFee, _totalAssets - calculatedProtocolFee);
        } else {
            return (calculatedProtocolFee, calculatedManagerFee);
        }
    }

    function managerFeeBeneficiary() internal view returns (address) {
        if (address(feeStrategy) == address(0)) {
            return getRoleMember(MANAGER_ROLE, 0);
        } else {
            return feeStrategy.managerFeeBeneficiary();
        }
    }

    function setTransferStrategy(ITransferStrategy _transferStrategy) public onlyRole(MANAGER_ROLE) {
        require(_transferStrategy != transferStrategy, "FlexiblePortfolio: New transfer strategy needs to be different");
        _setTransferStrategy(_transferStrategy);
    }

    function _setTransferStrategy(ITransferStrategy _transferStrategy) internal {
        emit TransferStrategyChanged(transferStrategy, _transferStrategy);
        transferStrategy = _transferStrategy;
    }

    function setFeeStrategy(IFeeStrategy _feeStrategy) public onlyRole(MANAGER_ROLE) {
        require(_feeStrategy != feeStrategy, "FlexiblePortfolio: New fee strategy needs to be different");
        _setFeeStrategy(_feeStrategy);
    }

    function _setFeeStrategy(IFeeStrategy _feeStrategy) internal {
        emit FeeStrategyChanged(feeStrategy, _feeStrategy);
        feeStrategy = _feeStrategy;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        if (address(transferStrategy) != address(0)) {
            require(
                ITransferStrategy(transferStrategy).canTransfer(sender, recipient, amount),
                "FlexiblePortfolio: This transfer not permitted"
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
