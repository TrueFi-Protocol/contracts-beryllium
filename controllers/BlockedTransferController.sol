// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ITransferController} from "../interfaces/ITransferController.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract BlockedTransferController is ITransferController, Initializable {
    function initialize() external initializer {}

    function canTransfer(
        address,
        address,
        uint256
    ) public pure returns (bool) {
        return false;
    }
}
