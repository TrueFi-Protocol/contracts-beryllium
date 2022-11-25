// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ILenderVerifier} from "../interfaces/ILenderVerifier.sol";

contract AllowAllLenderVerifier is ILenderVerifier {
    function isAllowed(address) external pure returns (bool) {
        return true;
    }
}
