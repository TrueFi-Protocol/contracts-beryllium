// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {FlexiblePortfolioFactory} from "./FlexiblePortfolioFactory.sol";
import {PermissionedPortfolio} from "./PermissionedPortfolio.sol";

contract PermissionedPortfolioFactory is FlexiblePortfolioFactory {
    address defaultForcedTransfersAdmin;

    function setupPortfolioInitData(
        IERC20Metadata _asset,
        uint256 _duration,
        uint256 _maxSize,
        IFlexiblePortfolio.Controllers memory controllers,
        IDebtInstrument[] calldata _allowedInstruments,
        IFlexiblePortfolio.ERC20Metadata calldata tokenMetadata
    ) internal view override returns (bytes memory) {
        require(defaultForcedTransfersAdmin != address(0), "PPF: Default forced transfers admin admin is not set");
        return
            abi.encodeWithSelector(
                PermissionedPortfolio.initializePermissioned.selector,
                protocolConfig,
                _duration,
                _asset,
                msg.sender,
                _maxSize,
                controllers,
                _allowedInstruments,
                tokenMetadata,
                defaultForcedTransfersAdmin
            );
    }

    function setDefaultForcedTransfersAdmin(address _defaultForcedTransfersAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_defaultForcedTransfersAdmin != address(0), "PPF: Default forced transfers admin cannot be address 0");
        require(
            _defaultForcedTransfersAdmin != defaultForcedTransfersAdmin,
            "PPF: Default forced transfers admin cannot be set to its current value"
        );
        defaultForcedTransfersAdmin = _defaultForcedTransfersAdmin;
    }
}
