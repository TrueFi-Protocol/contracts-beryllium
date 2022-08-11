// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IValuationStrategy} from "./interfaces/IValuationStrategy.sol";
import {BasePortfolioFactory} from "./BasePortfolioFactory.sol";

contract FlexiblePortfolioFactory is BasePortfolioFactory {
    function createPortfolio(
        IERC20WithDecimals _asset,
        uint256 _duration,
        uint256 _maxSize,
        IFlexiblePortfolio.Strategies calldata strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        uint256 _managerFee,
        IFlexiblePortfolio.ERC20Metadata calldata tokenMetadata
    ) external onlyRole(MANAGER_ROLE) {
        bytes memory initCalldata = abi.encodeWithSelector(
            IFlexiblePortfolio.initialize.selector,
            protocolConfig,
            _duration,
            _asset,
            msg.sender,
            _maxSize,
            strategies,
            _allowedInstruments,
            _managerFee,
            tokenMetadata
        );
        _deployPortfolio(initCalldata);
    }
}
