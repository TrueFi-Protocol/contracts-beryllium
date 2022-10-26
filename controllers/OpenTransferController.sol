// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ITransferController} from "../interfaces/ITransferController.sol";

contract OpenTransferController is ITransferController {
    function canTransfer(
        address,
        address,
        uint256
    ) public pure returns (bool) {
        return true;
    }
}