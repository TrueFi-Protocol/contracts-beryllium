// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAutomatedLineOfCredit} from "../interfaces/IAutomatedLineOfCredit.sol";
import {AutomatedLineOfCreditFactory} from "../AutomatedLineOfCreditFactory.sol";

contract OpenAutomatedLineOfCreditFactory is AutomatedLineOfCreditFactory {
    function createPortfolio(
        uint256 _duration,
        IERC20Metadata _asset,
        uint256 _maxSize,
        IAutomatedLineOfCredit.InterestRateParameters calldata _interestRateParameters,
        ControllersData calldata controllersData,
        string calldata name,
        string calldata symbol
    ) external override {
        _createPortfolio(_duration, _asset, _maxSize, _interestRateParameters, controllersData, name, symbol);
    }
}
