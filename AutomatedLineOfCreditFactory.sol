// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAutomatedLineOfCredit} from "./interfaces/IAutomatedLineOfCredit.sol";
import {PortfolioFactory} from "./PortfolioFactory.sol";

contract AutomatedLineOfCreditFactory is PortfolioFactory {
    function createPortfolio(
        uint256 _duration,
        IERC20Metadata _asset,
        uint256 _maxSize,
        IAutomatedLineOfCredit.InterestRateParameters memory _interestRateParameters,
        address _depositController,
        address _withdrawStrategy,
        address _transferStrategy,
        string calldata name,
        string calldata symbol
    ) external onlyRole(MANAGER_ROLE) {
        bytes memory initCalldata = abi.encodeWithSelector(
            IAutomatedLineOfCredit.initialize.selector,
            protocolConfig,
            _duration,
            _asset,
            msg.sender,
            _maxSize,
            _interestRateParameters,
            _depositController,
            _withdrawStrategy,
            _transferStrategy,
            name,
            symbol
        );
        _deployPortfolio(initCalldata);
    }
}
