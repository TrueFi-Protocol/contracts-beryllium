// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IFeeStrategy} from "../interfaces/IFeeStrategy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract FeeStrategy is IFeeStrategy, Initializable {
    uint256 public managerFeeRate;

    function initialize(uint256 _managerFeeRate) external initializer {
        managerFeeRate = _managerFeeRate;
    }
}
