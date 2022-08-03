// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ITransferStrategy} from "../interfaces/ITransferStrategy.sol";

contract SimpleTransferStrategy is ITransferStrategy {
    function canTransfer(
        address,
        address,
        uint256
    ) public pure returns (bool) {
        return true;
    }
}
