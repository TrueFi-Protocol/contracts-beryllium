// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract BasicContract {
    uint256 public num;

    constructor(uint256 _num) {
        num = _num;
    }

    function add(uint256 amount) public {
        num = num + amount;
    }
}
