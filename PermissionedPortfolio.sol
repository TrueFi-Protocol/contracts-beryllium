// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {FlexiblePortfolio} from "./FlexiblePortfolio.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDepositController} from "./interfaces/IDepositController.sol";
import {IWithdrawController} from "./interfaces/IWithdrawController.sol";

contract PermissionedPortfolio is FlexiblePortfolio {
    // Name "ControllerTransfer" comes from EIP-1644 standard
    // https://github.com/SecurityTokenStandard/EIP-Spec/blob/master/eip/eip-1644.md
    event ControllerTransfer(address _forcedTransfersAdmin, address indexed _from, address indexed _to, uint256 _value);
    bytes32 public constant FORCED_TRANSFERS_ADMIN_ROLE = keccak256("FORCED_TRANSFERS_ADMIN_ROLE");

    function initializePermissioned(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20Metadata _asset,
        address _manager,
        uint256 _maxSize,
        Controllers calldata _controllers,
        IDebtInstrument[] calldata _allowedInstruments,
        ERC20Metadata calldata tokenMetadata,
        address _forcedTransfersAdmin
    ) external initializer {
        require(_forcedTransfersAdmin != address(0), "PP: Forced trasfers admin cannot be address 0");

        require(_duration > 0, "FP:Duration can't be 0");
        __Upgradeable_init(_protocolConfig.protocolAdmin(), _protocolConfig.pauserAddress());
        __ERC20_init(tokenMetadata.name, tokenMetadata.symbol);
        _grantRole(MANAGER_ROLE, _manager);
        _grantRole(CONTROLLER_ADMIN_ROLE, _manager);
        _setManagerFeeBeneficiary(_manager);
        protocolConfig = _protocolConfig;
        endDate = block.timestamp + _duration;
        asset = _asset;
        maxSize = _maxSize;
        _decimals = _asset.decimals();
        __setDepositController(_controllers.depositController);
        __setWithdrawController(_controllers.withdrawController);
        _setTransferController(_controllers.transferController);
        _setFeeStrategy(_controllers.feeStrategy);
        valuationStrategy = _controllers.valuationStrategy;

        for (uint256 i; i < _allowedInstruments.length; i++) {
            isInstrumentAllowed[_allowedInstruments[i]] = true;
        }

        _grantRole(FORCED_TRANSFERS_ADMIN_ROLE, _forcedTransfersAdmin);
        _setRoleAdmin(FORCED_TRANSFERS_ADMIN_ROLE, FORCED_TRANSFERS_ADMIN_ROLE);
    }

    function __setDepositController(IDepositController _depositController) private {
        depositController = _depositController;
        emit DepositControllerChanged(_depositController);
    }

    function __setWithdrawController(IWithdrawController _withdrawController) private {
        withdrawController = _withdrawController;
        emit WithdrawControllerChanged(_withdrawController);
    }

    // Name "controllerTransfer" comes from EIP-1644 standard
    // https://github.com/SecurityTokenStandard/EIP-Spec/blob/master/eip/eip-1644.md
    function controllerTransfer(
        address _from,
        address _to,
        uint256 _value
    ) external whenNotPaused onlyRole(FORCED_TRANSFERS_ADMIN_ROLE) {
        _transfer(_from, _to, _value);
        emit ControllerTransfer(msg.sender, _from, _to, _value);
    }
}
