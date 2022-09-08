// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract DummyContract {
    uint256 private value = 5;

    function getValue() public view returns (uint256) {
        return value;
    }
}
