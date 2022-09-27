// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../FlexiblePortfolio.sol";

contract FlexiblePortfolioHarness is FlexiblePortfolio {
    function getBytes4(bytes calldata callData) public pure returns (bytes4) {
        return bytes4(callData);
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

    function managerFeeBeneficiaryHarness() public view returns (address) {
        return managerFeeBeneficiary;
    }

    function highestInstrumentEndDateHarness() public view returns (uint256) {
        return highestInstrumentEndDate;
    }

    function lastUpdateTimeHarness() public view returns (uint256) {
        return lastUpdateTime;
    }

    function payManagerFeeHarness(
        uint256 continuousFee,
        uint256 actionFee,
        uint256 liquidity
    ) public returns (uint256) {
        return payManagerFee(continuousFee, actionFee, liquidity);
    }

    function payProtocolFeeHarness(uint256 _fee, uint256 balance) public returns (uint256) {
        return payProtocolFee(_fee, balance);
    }
}