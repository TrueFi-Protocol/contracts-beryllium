// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

contract AllowAllLenderVerifier {
    function isAllowed(address) external pure returns (bool) {
        return true;
    }
}
