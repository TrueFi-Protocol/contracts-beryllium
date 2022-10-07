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

    //    function _previewMintHarness(uint256 shares, uint256 _totalAssets) public view returns (uint256) {
    //        return _previewMint(shares, _totalAssets);
    //    }

    function highestInstrumentEndDateHarness() public view returns (uint256) {
        return highestInstrumentEndDate;
    }

    function lastUpdateTimeHarness() public view returns (uint256) {
        return lastUpdateTime;
    }
}
