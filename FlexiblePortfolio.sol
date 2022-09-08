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
    uint256 public lastProtocolFeeRate;
    uint256 public lastManagerFeeRate;
    uint256 public unpaidProtocolFee;
    uint256 public unpaidManagerFee;
    uint256 internal lastUpdateTime;
    uint256 internal highestInstrumentEndDate;

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
        require(_duration > 0, "FP:Duration can't be 0");
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
        require(_withdrawStrategy != withdrawStrategy, "FP:Value has to be different");
        _setWithdrawStrategy(_withdrawStrategy);
    }

    function _setWithdrawStrategy(IWithdrawStrategy _withdrawStrategy) private {
        emit WithdrawStrategyChanged(withdrawStrategy, _withdrawStrategy);
        withdrawStrategy = _withdrawStrategy;
    }

    function setDepositStrategy(IDepositStrategy _depositStrategy) public onlyRole(MANAGER_ROLE) {
        require(_depositStrategy != depositStrategy, "FP:Value has to be different");
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
        require(isInstrumentAllowed[instrument], "FP:Instrument not allowed");
        require(instrument.issueInstrumentSelector() == bytes4(issueInstrumentCalldata), "FP:Invalid function call");

        bytes memory result = address(instrument).functionCall(issueInstrumentCalldata);

        uint256 instrumentId = abi.decode(result, (uint256));
        require(instrument.asset(instrumentId) == asset, "FP:Token mismatch");
        isInstrumentAdded[instrument][instrumentId] = true;
        emit InstrumentAdded(instrument, instrumentId);

        return instrumentId;
    }

    function fundInstrument(IDebtInstrument instrument, uint256 instrumentId) public onlyRole(MANAGER_ROLE) {
        require(isInstrumentAdded[instrument][instrumentId], "FP:Instrument not added");
        address borrower = instrument.recipient(instrumentId);
        uint256 principalAmount = instrument.principal(instrumentId);
        (, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 totalFee = protocolFee + managerFee;
        require(totalFee + principalAmount <= virtualTokenBalance, "FP:Not enough liquidity");
        instrument.start(instrumentId);
        uint256 instrumentEndDate = instrument.endDate(instrumentId);
        require(instrumentEndDate <= endDate, "FP:Instrument has bigger endDate");
        updateHighestInstrumentEndDate(instrumentEndDate);

        valuationStrategy.onInstrumentFunded(this, instrument, instrumentId);
        asset.safeTransfer(borrower, principalAmount);
        _payFeeAndUpdate(protocolFee, managerFee, 0, virtualTokenBalance - principalAmount);
        emit InstrumentFunded(instrument, instrumentId);
    }

    function updateInstrument(IDebtInstrument instrument, bytes calldata updateInstrumentCalldata) external onlyRole(MANAGER_ROLE) {
        require(isInstrumentAllowed[instrument], "FP:Instrument not allowed");
        require(instrument.updateInstrumentSelector() == bytes4(updateInstrumentCalldata), "FP:Invalid function call");

        address(instrument).functionCall(updateInstrumentCalldata);
        emit InstrumentUpdated(instrument);
    }

    function updateHighestInstrumentEndDate(uint256 instrumentEndDate) internal {
        if (instrumentEndDate > highestInstrumentEndDate) {
            highestInstrumentEndDate = instrumentEndDate;
        }
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        require(block.timestamp < endDate, "FP:End date elapsed");
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
        require(assets >= depositFee, "FP:Fee bigger than assets");
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 assetsAfterDepositFee = assets - depositFee;
        _checkDeposit(receiver, _totalAssets, assetsAfterDepositFee, depositAllowed);

        uint256 sharesToMint = _convertToShares(assetsAfterDepositFee, _totalAssets);
        require(sharesToMint > 0, "FP:Amount can't be 0");

        _mint(receiver, sharesToMint);
        asset.safeTransferFrom(msg.sender, address(this), assetsAfterDepositFee);
        _payFeeAndUpdate(protocolFee, managerFee, depositFee, virtualTokenBalance + assets);

        emit Deposit(msg.sender, receiver, assetsAfterDepositFee, sharesToMint);
        return sharesToMint;
    }

    function _checkDeposit(
        address receiver,
        uint256 _totalAssets,
        uint256 assets,
        bool depositAllowed
    ) internal view {
        require(depositAllowed, "FP:Operation not allowed");
        require(assets + _totalAssets <= maxSize, "FP:Portfolio is full");
        require(block.timestamp < endDate, "FP:End date elapsed");
        require(receiver != address(this), "FP:Wrong receiver/owner");
    }

    function mint(uint256 shares, address receiver) public whenNotPaused returns (uint256) {
        (uint256 _totalAssets, uint256 protocolFee, uint256 managerFee) = getTotalAssetsAndFee();
        uint256 assets = _previewMint(shares, _totalAssets);
        (bool depositAllowed, uint256 mintFee) = onMint(msg.sender, assets, receiver);
        uint256 assetsWithMintFee = assets + mintFee;
        _checkDeposit(receiver, _totalAssets, assets, depositAllowed);

        _mint(receiver, shares);
        asset.safeTransferFrom(msg.sender, address(this), assetsWithMintFee);
        _payFeeAndUpdate(protocolFee, managerFee, mintFee, virtualTokenBalance + assetsWithMintFee);

        emit Deposit(msg.sender, receiver, assets, shares);
        return assetsWithMintFee + protocolFee + managerFee;
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        require(block.timestamp < endDate, "FP:End date elapsed");
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
        require(assets >= redeemFee, "FP:Fee bigger than assets");
        require(withdrawAllowed, "FP:Operation not allowed");
        require(assets + protocolFee + managerFee <= virtualTokenBalance, "FP:Not enough liquidity");

        uint256 assetsAfterRedeemFee = assets - redeemFee;
        _executeWithdraw(owner, receiver, shares, assetsAfterRedeemFee);
        _payFeeAndUpdate(protocolFee, managerFee, redeemFee, virtualTokenBalance - assetsAfterRedeemFee);
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
        require(amount > 0, "FP:Amount can't be 0");
        require(instrument.recipient(instrumentId) == msg.sender, "FP:Wrong recipient");
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
        lastProtocolFeeRate = protocolConfig.protocolFeeRate();
        lastManagerFeeRate = address(feeStrategy) != address(0x00) ? feeStrategy.managerFeeRate() : 0;
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
        require(_valuationStrategy != valuationStrategy, "FP:Value has to be different");
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
        uint256 unpaidFees = unpaidProtocolFee + unpaidManagerFee;
        return unpaidFees > _totalAssets ? 0 : _totalAssets - unpaidFees;
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
        return (
            assetsBeforeFee - accruedProtocolFee - accruedManagerFee,
            accruedProtocolFee + unpaidProtocolFee,
            accruedManagerFee + unpaidManagerFee
        );
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
        uint256 fee = _getPreviewRedeemFee(shares);
        uint256 assets = convertToAssets(shares);
        return fee < assets ? assets - fee : 0;
    }

    function _getPreviewRedeemFee(uint256 shares) internal view returns (uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.previewRedeemFee(shares);
        } else {
            return 0;
        }
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
        require(_maxSize != maxSize, "FP:Value has to be different");
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
            require(allowed >= shares, "FP:Not enough allowance");
            _approve(owner, msg.sender, allowed - shares);
        }
        _burn(owner, shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _previewWithdraw(assets + _getPreviewWithdrawFee(assets), totalAssets());
    }

    function _getPreviewWithdrawFee(uint256 assets) internal view returns (uint256) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.previewWithdrawFee(assets);
        } else {
            return 0;
        }
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
        require(withdrawAllowed, "FP:Operation not allowed");
        require(receiver != address(this) && owner != address(this), "FP:Wrong receiver/owner");
        require(assets > 0, "FP:Amount can't be 0");
        require(assets + withdrawFee + protocolFee + managerFee <= virtualTokenBalance, "FP:Not enough liquidity");

        _executeWithdraw(owner, receiver, shares, assets);

        _payFeeAndUpdate(protocolFee, managerFee, withdrawFee, virtualTokenBalance - assets);
        return shares;
    }

    function _executeWithdraw(
        address owner,
        address receiver,
        uint256 shares,
        uint256 assets
    ) internal {
        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function accruedFee() external view returns (uint256 accruedProtocolFee, uint256 accruedManagerFee) {
        return _accruedFee(totalAssetsBeforeAccruedFee());
    }

    function _accruedFee(uint256 _totalAssets) internal view returns (uint256 accruedProtocolFee, uint256 accruedManagerFee) {
        uint256 adjustedTotalAssets = (block.timestamp - lastUpdateTime) * _totalAssets;
        uint256 calculatedProtocolFee = (adjustedTotalAssets * lastProtocolFeeRate) / YEAR / BASIS_PRECISION;
        if (calculatedProtocolFee > _totalAssets) {
            return (_totalAssets, 0);
        }
        uint256 calculatedManagerFee = (adjustedTotalAssets * lastManagerFeeRate) / YEAR / BASIS_PRECISION;
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
        require(_transferStrategy != transferStrategy, "FP:Value has to be different");
        _setTransferStrategy(_transferStrategy);
    }

    function _setTransferStrategy(ITransferStrategy _transferStrategy) internal {
        emit TransferStrategyChanged(transferStrategy, _transferStrategy);
        transferStrategy = _transferStrategy;
    }

    function setFeeStrategy(IFeeStrategy _feeStrategy) public onlyRole(MANAGER_ROLE) {
        require(_feeStrategy != feeStrategy, "FP:Value has to be different");
        _setFeeStrategy(_feeStrategy);
    }

    function _setFeeStrategy(IFeeStrategy _feeStrategy) internal {
        emit FeeStrategyChanged(feeStrategy, _feeStrategy);
        feeStrategy = _feeStrategy;
    }

    function setEndDate(uint256 newEndDate) external onlyRole(MANAGER_ROLE) {
        require(endDate > block.timestamp, "FP:End date elapsed");
        require(
            newEndDate < endDate && newEndDate > highestInstrumentEndDate && newEndDate > block.timestamp,
            "FP:New endDate too big"
        );
        endDate = newEndDate;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override whenNotPaused {
        if (address(transferStrategy) != address(0)) {
            require(ITransferStrategy(transferStrategy).canTransfer(sender, recipient, amount), "FP:Operation not allowed");
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
