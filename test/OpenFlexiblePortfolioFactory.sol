// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IFlexiblePortfolio} from "../interfaces/IFlexiblePortfolio.sol";
import {IDebtInstrument} from "../interfaces/IDebtInstrument.sol";
import {FlexiblePortfolioFactory} from "../FlexiblePortfolioFactory.sol";

contract OpenFlexiblePortfolioFactory is FlexiblePortfolioFactory {
    function createPortfolio(
        IERC20Metadata _asset,
        uint256 _duration,
        uint256 _maxSize,
        ControllersData memory controllersData,
        IDebtInstrument[] calldata _allowedInstruments,
        IFlexiblePortfolio.ERC20Metadata calldata tokenMetadata
    ) public override {
        IFlexiblePortfolio.Controllers memory controllers = setupControllers(controllersData);
        bytes memory initCalldata = setupPortfolioInitData(
            _asset,
            _duration,
            _maxSize,
            controllers,
            _allowedInstruments,
            tokenMetadata
        );
        _deployPortfolio(initCalldata);
    }
}
