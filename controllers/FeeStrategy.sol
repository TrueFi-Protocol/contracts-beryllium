// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFeeStrategy} from "../interfaces/IFeeStrategy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract FeeStrategy is IFeeStrategy, Initializable, AccessControlEnumerable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public managerFeeRate;

    event ManagerFeeRateChanged(uint256 newManagerFeeRate);

    function initialize(address manager, uint256 _managerFeeRate) external initializer {
        _setRoleAdmin(MANAGER_ROLE, MANAGER_ROLE);
        _grantRole(MANAGER_ROLE, manager);
        managerFeeRate = _managerFeeRate;
    }

    function setManagerFeeRate(uint256 newManagerFeeRate) external onlyRole(MANAGER_ROLE) {
        managerFeeRate = newManagerFeeRate;
        emit ManagerFeeRateChanged(newManagerFeeRate);
    }
}
