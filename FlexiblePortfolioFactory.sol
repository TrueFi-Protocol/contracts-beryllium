// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IValuationStrategy} from "./interfaces/IValuationStrategy.sol";
import {PortfolioFactory} from "./PortfolioFactory.sol";

contract FlexiblePortfolioFactory is PortfolioFactory {
    function createPortfolio(
        IERC20Metadata _asset,
        uint256 _duration,
        uint256 _maxSize,
        IFlexiblePortfolio.Strategies calldata strategies,
        IDebtInstrument[] calldata _allowedInstruments,
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
            tokenMetadata
        );
        _deployPortfolio(initCalldata);
    }
}
