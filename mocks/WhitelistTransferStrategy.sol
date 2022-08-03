// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBasePortfolio} from "../interfaces/IBasePortfolio.sol";

import {ITransferStrategy} from "../interfaces/ITransferStrategy.sol";

contract WhitelistTransferStrategy is ITransferStrategy {
    mapping(address => mapping(address => bool)) public isWhitelisted;

    function canTransfer(
        address sender,
        address recipient,
        uint256
    ) public view returns (bool) {
        return isWhitelisted[sender][recipient];
    }

    function setWhitelistStatus(
        IBasePortfolio portfolio,
        address sender,
        address recipient,
        bool status
    ) external {
        require(
            portfolio.hasRole(portfolio.MANAGER_ROLE(), msg.sender),
            "WhitelistTransferStrategy: Only portfolio manager can change whitelist status"
        );
        isWhitelisted[sender][recipient] = status;
    }
}
