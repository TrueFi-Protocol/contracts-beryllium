// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ITransferController} from "../interfaces/ITransferController.sol";
import {IAccessControl} from "../interfaces/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract WhitelistTransferController is ITransferController, Initializable {
    mapping(address => mapping(address => bool)) public isWhitelisted;

    function initialize() external initializer {}

    function canTransfer(
        address sender,
        address recipient,
        uint256
    ) public view returns (bool) {
        return isWhitelisted[sender][recipient];
    }

    function setWhitelistStatus(
        IAccessControl portfolio,
        address sender,
        address recipient,
        bool status
    ) external {
        require(
            portfolio.hasRole(portfolio.MANAGER_ROLE(), msg.sender),
            "WhitelistTransferController: Only portfolio manager can change whitelist status"
        );
        isWhitelisted[sender][recipient] = status;
    }
}
