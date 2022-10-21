// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFlexiblePortfolio} from "./interfaces/IFlexiblePortfolio.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDebtInstrument} from "./interfaces/IDebtInstrument.sol";
import {IValuationStrategy} from "./interfaces/IValuationStrategy.sol";
import {PortfolioFactory} from "./PortfolioFactory.sol";
import {FeeStrategy, IFeeStrategy} from "./controllers/FeeStrategy.sol";

contract FlexiblePortfolioFactory is PortfolioFactory {
    event FeeStrategyCreated(address indexed feeStrategy, uint256 managerFeeRate);

    function createPortfolio(
        IERC20Metadata _asset,
        uint256 _duration,
        uint256 _maxSize,
        IFlexiblePortfolio.Strategies memory strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        IFlexiblePortfolio.ERC20Metadata calldata tokenMetadata
    ) public onlyRole(MANAGER_ROLE) {
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

    function createPortfolioAndFeeStrategy(
        IERC20Metadata _asset,
        uint256 _duration,
        uint256 _maxSize,
        uint256 managerFeeRate,
        IFlexiblePortfolio.Strategies calldata _strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        IFlexiblePortfolio.ERC20Metadata calldata tokenMetadata
    ) external onlyRole(MANAGER_ROLE) {
        IFeeStrategy feeStrategy = new FeeStrategy(msg.sender, managerFeeRate);
        emit FeeStrategyCreated(address(feeStrategy), managerFeeRate);

        IFlexiblePortfolio.Strategies memory strategies = IFlexiblePortfolio.Strategies(
            _strategies.depositController,
            _strategies.withdrawController,
            _strategies.transferStrategy,
            _strategies.valuationStrategy,
            feeStrategy
        );
        createPortfolio(_asset, _duration, _maxSize, strategies, _allowedInstruments, tokenMetadata);
    }
}
