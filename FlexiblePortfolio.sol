// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IBasePortfolio, IERC4626} from "./interfaces/IBasePortfolio.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IValuationStrategy} from "./interfaces/IValuationStrategy.sol";
import {ITransferStrategy} from "./interfaces/ITransferStrategy.sol";
import {IDepositStrategy} from "./interfaces/IDepositStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BasePortfolio} from "./BasePortfolio.sol";

contract FlexiblePortfolio is IFlexiblePortfolio, BasePortfolio {
    uint256 private constant PRECISION = 1e30;

    using SafeERC20 for IERC20WithDecimals;
    using Address for address;

    mapping(IDebtInstrument => bool) public isInstrumentAllowed;

    uint8 internal _decimals;
    uint256 public maxValue;
    IValuationStrategy public valuationStrategy;
    IDepositStrategy public depositStrategy;
    IWithdrawStrategy public withdrawStrategy;

    mapping(IDebtInstrument => mapping(uint256 => bool)) public isInstrumentAdded;

    event InstrumentAdded(IDebtInstrument indexed instrument, uint256 indexed instrumentId);
    event InstrumentFunded(IDebtInstrument indexed instrument, uint256 indexed instrumentId);
    event InstrumentUpdated(IDebtInstrument indexed instrument);
    event AllowedInstrumentChanged(IDebtInstrument indexed instrument, bool isAllowed);
    event ValuationStrategyChanged(IValuationStrategy indexed strategy);
    event InstrumentRepaid(IDebtInstrument indexed instrument, uint256 indexed instrumentId, uint256 amount);
    event ManagerFeeChanged(uint256 newManagerFee);
    event MaxValueChanged(uint256 newMaxValue);
    event DepositStrategyChanged(IDepositStrategy indexed oldStrategy, IDepositStrategy indexed newStrategy);
    event WithdrawStrategyChanged(IWithdrawStrategy indexed oldStrategy, IWithdrawStrategy indexed newStrategy);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
        address _manager,
        uint256 _maxValue,
        Strategies calldata _strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        uint256 _managerFee,
        ERC20Metadata calldata tokenMetadata
    ) external initializer {
        __BasePortfolio_init(_protocolConfig, _duration, _asset, _manager, _managerFee);
        __ERC20_init(tokenMetadata.name, tokenMetadata.symbol);
        maxValue = _maxValue;
        _decimals = _asset.decimals();
        _setWithdrawStrategy(_strategies.withdrawStrategy);
        _setDepositStrategy(_strategies.depositStrategy);
        _setTransferStrategy(_strategies.transferStrategy);
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
        require(principalAmount <= virtualTokenBalance, "FlexiblePortfolio: Insufficient funds in portfolio to fund loan");
        instrument.start(instrumentId);
        require(
            instrument.endDate(instrumentId) <= endDate,
            "FlexiblePortfolio: Cannot fund instrument which end date is after portfolio end date"
        );
        valuationStrategy.onInstrumentFunded(this, instrument, instrumentId);
        asset.safeTransfer(borrower, principalAmount);
        virtualTokenBalance -= principalAmount;
        emit InstrumentFunded(instrument, instrumentId);
    }

    function updateInstrument(IDebtInstrument instrument, bytes calldata updateInstrumentCalldata) external onlyRole(MANAGER_ROLE) {
        require(isInstrumentAllowed[instrument], "FlexiblePortfolio: Instrument is not allowed");
        require(instrument.updateInstrumentSelector() == bytes4(updateInstrumentCalldata), "FlexiblePortfolio: Invalid function call");

        address(instrument).functionCall(updateInstrumentCalldata);
        emit InstrumentUpdated(instrument);
    }

    function _previewDeposit(uint256 amount)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 managersPart = (amount * managerFee) / BASIS_PRECISION;
        uint256 protocolsPart = (amount * protocolConfig.protocolFee()) / BASIS_PRECISION;
        require(protocolsPart + managersPart <= amount, "FlexiblePortfolio: Fee cannot exceed deposited amount");
        uint256 amountToDeposit = amount - managersPart - protocolsPart;
        return (amountToDeposit, managersPart, protocolsPart);
    }

    function previewDeposit(uint256 amount) public view returns (uint256) {
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");
        (uint256 amountToDeposit, , ) = _previewDeposit(amount);
        return convertToShares(amountToDeposit);
    }

    /* @notice This contract is upgradeable and interacts with settable deposit strategies,
     * that may change over the contract's lifespan. As a safety measure, we recommend approving
     * this contract with the desired deposit amount instead of performing infinite allowance.
     */
    function deposit(uint256 assets, address receiver) public override(BasePortfolio, IERC4626) whenNotPaused returns (uint256) {
        require(isDepositAllowed(msg.sender, assets), "FlexiblePortfolio: Deposit not allowed");
        require(assets + totalAssets() <= maxValue, "FlexiblePortfolio: Deposit would cause pool to exceed max size");
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");
        require(receiver != address(this), "FlexiblePortfolio: Portfolio cannot be deposit receiver");

        address protocolAddress = protocolConfig.protocolAddress();
        address manager = getRoleMember(MANAGER_ROLE, 0);
        (uint256 amountToDeposit, uint256 managersPart, uint256 protocolsPart) = _previewDeposit(assets);

        uint256 sharesToMint = convertToShares(amountToDeposit);
        require(sharesToMint > 0, "FlexiblePortfolio: Cannot mint 0 shares");

        _mint(receiver, sharesToMint);
        virtualTokenBalance += amountToDeposit;

        asset.safeTransferFrom(msg.sender, address(this), amountToDeposit);
        asset.safeTransferFrom(msg.sender, manager, managersPart);
        asset.safeTransferFrom(msg.sender, protocolAddress, protocolsPart);

        emit FeePaid(msg.sender, manager, managersPart);
        emit FeePaid(msg.sender, protocolAddress, protocolsPart);
        emit Deposit(msg.sender, receiver, assets, sharesToMint);

        return sharesToMint;
    }

    function mint(uint256 shares, address receiver) public whenNotPaused returns (uint256) {
        uint256 assets = totalSupply() == 0 ? shares : convertToAssetsRoundUp(shares);
        require(isDepositAllowed(msg.sender, assets), "FlexiblePortfolio: Sender not allowed to mint");
        require(assets + totalAssets() <= maxValue, "FlexiblePortfolio: Portfolio is full");
        require(block.timestamp < endDate, "FlexiblePortfolio: Portfolio end date has elapsed");

        uint256 _totalFee = totalFee();
        uint256 assetsPlusFee = assetsBeforeFees(assets, _totalFee);

        _mint(receiver, shares);
        virtualTokenBalance += assets;

        asset.safeTransferFrom(msg.sender, address(this), assets);
        payFees(assetsPlusFee - assets, _totalFee);

        emit Deposit(msg.sender, receiver, assetsPlusFee, shares);
        return assetsPlusFee;
    }

    function payFees(uint256 feeAmount, uint256 _totalFee) internal {
        if (_totalFee == 0) {
            return;
        }
        address protocolAddress = protocolConfig.protocolAddress();
        address manager = getRoleMember(MANAGER_ROLE, 0);
        uint256 managersPart = (feeAmount * managerFee) / _totalFee;
        uint256 protocolsPart = feeAmount - managersPart;

        payFee(msg.sender, manager, managersPart);
        payFee(msg.sender, protocolAddress, protocolsPart);
    }

    function payFee(
        address from,
        address to,
        uint256 fee
    ) internal {
        asset.safeTransferFrom(from, to, fee);
        emit FeePaid(from, to, fee);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 assetsAfterFees = totalSupply() == 0 ? shares : convertToAssetsRoundUp(shares);
        uint256 _totalFee = totalFee();
        return assetsBeforeFees(assetsAfterFees, _totalFee);
    }

    function assetsBeforeFees(uint256 assetsAfterFees, uint256 _totalFee) internal pure returns (uint256) {
        return (assetsAfterFees * BASIS_PRECISION) / (BASIS_PRECISION - _totalFee);
    }

    function totalFee() internal view virtual returns (uint256) {
        uint256 _totalFee = protocolConfig.protocolFee() + managerFee;
        return _totalFee < BASIS_PRECISION ? _totalFee : BASIS_PRECISION;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual whenNotPaused returns (uint256) {
        uint256 redeemedAssets = convertToAssets(shares);
        require(isWithdrawAllowed(msg.sender, redeemedAssets), "FlexiblePortfolio: Withdraw not allowed");
        require(redeemedAssets <= virtualTokenBalance, "FlexiblePortfolio: Amount exceeds pool balance");

        virtualTokenBalance -= redeemedAssets;
        _burnFrom(owner, msg.sender, shares);
        asset.safeTransfer(receiver, redeemedAssets);
        emit Withdraw(msg.sender, receiver, owner, redeemedAssets, shares);
        return redeemedAssets;
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
        instrument.repay(instrumentId, amount);
        valuationStrategy.onInstrumentUpdated(this, instrument, instrumentId);

        instrument.asset(instrumentId).safeTransferFrom(msg.sender, address(this), amount);
        virtualTokenBalance += amount;
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

    function setValuationStrategy(IValuationStrategy _valuationStrategy) external onlyRole(MANAGER_ROLE) {
        require(_valuationStrategy != valuationStrategy, "FlexiblePortfolio: New valuation strategy needs to be different");
        valuationStrategy = _valuationStrategy;
        emit ValuationStrategyChanged(_valuationStrategy);
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return (sharesAmount * totalAssets()) / _totalSupply;
    }

    function convertToAssetsRoundUp(uint256 sharesAmount) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }
        return Math.ceilDiv(sharesAmount * totalAssets(), _totalSupply);
    }

    function totalAssets() public view override(IERC4626, BasePortfolio) returns (uint256) {
        if (address(valuationStrategy) == address(0)) {
            return 0;
        }
        return virtualTokenBalance + valuationStrategy.calculateValue(this);
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

    function maxMint(address receiver) public view returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function liquidValue() public view returns (uint256) {
        return virtualTokenBalance;
    }

    function setManagerFee(uint256 newManagerFee) external onlyRole(MANAGER_ROLE) {
        require(newManagerFee != managerFee, "FlexiblePortfolio: New manager fee needs to be different");
        managerFee = newManagerFee;
        emit ManagerFeeChanged(newManagerFee);
    }

    function maxDeposit(address receiver) public view returns (uint256) {
        if (paused() || block.timestamp >= endDate) {
            return 0;
        }
        uint256 _totalAssets = totalAssets();
        if (_totalAssets >= maxValue) {
            return 0;
        } else {
            return min(maxValue - _totalAssets, getMaxDepositFromStrategy(receiver));
        }
    }

    function maxWithdraw(address) public pure returns (uint256) {
        return 0;
    }

    function setMaxValue(uint256 _maxValue) external onlyRole(MANAGER_ROLE) {
        require(_maxValue != maxValue, "FlexiblePortfolio: New max value needs to be different");
        maxValue = _maxValue;
        emit MaxValueChanged(_maxValue);
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

    function isWithdrawAllowed(address sender, uint256 amount) internal view returns (bool) {
        if (address(withdrawStrategy) != address(0x00)) {
            return withdrawStrategy.isWithdrawAllowed(sender, amount);
        } else {
            return true;
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

    function previewWithdraw(uint256) public pure returns (uint256) {
        return 0;
    }

    function withdraw(
        uint256,
        address,
        address
    ) public pure returns (uint256) {
        return 0;
    }
}
