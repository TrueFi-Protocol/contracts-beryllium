// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFlexiblePortfolio} from "../interfaces/IFlexiblePortfolio.sol";
import {IDebtInstrument} from "../interfaces/IDebtInstrument.sol";
import {IValuationStrategy} from "../interfaces/IValuationStrategy.sol";

contract MockParentStrategy is IValuationStrategy {
    IValuationStrategy public loanValuationStrategy;

    function initialize(IValuationStrategy _loanValuationStrategy) external {
        loanValuationStrategy = _loanValuationStrategy;
    }

    function onInstrumentFunded(
        IFlexiblePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external {
        loanValuationStrategy.onInstrumentFunded(portfolio, instrument, instrumentId);
    }

    function onInstrumentUpdated(
        IFlexiblePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external {
        loanValuationStrategy.onInstrumentUpdated(portfolio, instrument, instrumentId);
    }

    function calculateValue(IFlexiblePortfolio) external pure returns (uint256) {
        return 0;
    }
}
