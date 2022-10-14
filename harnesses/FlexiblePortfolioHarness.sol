// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../FlexiblePortfolio.sol";
import {IFixedInterestOnlyLoans} from "../interfaces/IFixedInterestOnlyLoans.sol";

contract FlexiblePortfolioHarness is FlexiblePortfolio {
    IFixedInterestOnlyLoans public fiol;

    function getBytes4(bytes calldata callData) public pure returns (bytes4) {
        return bytes4(callData);
    }

    function addInstrumentFIOL(
        IDebtInstrument instrument,
        IERC20Metadata _asset,
        uint256 _principal,
        uint16 _periodCount,
        uint256 _periodPayment,
        uint32 _periodDuration,
        address _recipient,
        uint32 _gracePeriod,
        bool _canBeRepaidAfterDefault
    ) external onlyRole(MANAGER_ROLE) returns (uint256) {
        require(isInstrumentAllowed[instrument], "FP:Instrument not allowed");
        uint256 instrumentId = fiol.issueLoan(
            _asset,
            _principal,
            _periodCount,
            _periodPayment,
            _periodDuration,
            _recipient,
            _gracePeriod,
            _canBeRepaidAfterDefault
        );
        require(instrument.asset(instrumentId) == asset, "FP:Token mismatch");
        isInstrumentAdded[instrument][instrumentId] = true;
        emit InstrumentAdded(instrument, instrumentId);

        return instrumentId;
    }

    function updateInstrumentFIOL(
        IDebtInstrument instrument,
        uint256 instrumentId,
        uint32 newGracePeriod
    ) external onlyRole(MANAGER_ROLE) {
        require(isInstrumentAllowed[instrument], "FP:Instrument not allowed");
        fiol.updateInstrument(instrumentId, newGracePeriod);
        emit InstrumentUpdated(instrument);
    }

    function getTotalAssetsAndFeeHarness()
        public
        view
        returns (
            uint256 totalAssetsAfterFee,
            uint256 protocolFee,
            uint256 managerFee
        )
    {
        return getTotalAssetsAndFee();
    }

    function highestInstrumentEndDateHarness() public view returns (uint256) {
        return highestInstrumentEndDate;
    }

    function lastUpdateTimeHarness() public view returns (uint256) {
        return lastUpdateTime;
    }
}
