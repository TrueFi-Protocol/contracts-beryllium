// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../FlexiblePortfolio.sol";

contract FlexiblePortfolioHarness is FlexiblePortfolio {
    function getBytes4(bytes calldata callData) public pure returns (bytes4) {
        return bytes4(callData);
    }
}
