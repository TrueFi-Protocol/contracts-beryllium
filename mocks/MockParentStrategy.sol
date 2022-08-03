// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBasePortfolio} from "../interfaces/IBasePortfolio.sol";
import {IDebtInstrument} from "../interfaces/IDebtInstrument.sol";
import {IValuationStrategy} from "../interfaces/IValuationStrategy.sol";

contract MockParentStrategy is IValuationStrategy {
    IValuationStrategy public loanValuationStrategy;

    function initialize(IValuationStrategy _loanValuationStrategy) external {
        loanValuationStrategy = _loanValuationStrategy;
    }

    function onInstrumentFunded(
        IBasePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external {
        loanValuationStrategy.onInstrumentFunded(portfolio, instrument, instrumentId);
    }

    function onInstrumentUpdated(
        IBasePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external {
        loanValuationStrategy.onInstrumentUpdated(portfolio, instrument, instrumentId);
    }

    function calculateValue(IBasePortfolio) external pure returns (uint256) {
        return 0;
    }
}
