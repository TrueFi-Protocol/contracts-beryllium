// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Upgradeable} from "../access/Upgradeable.sol";

contract TestUpgradeable is Upgradeable {
    function initialize(address pauser) external initializer {
        __Upgradeable_init(msg.sender, pauser);
    }

    function falseWhenNotPaused() external view whenNotPaused returns (bool) {
        return paused();
    }

    function trueWhenPaused() external view whenPaused returns (bool) {
        return paused();
    }
}
