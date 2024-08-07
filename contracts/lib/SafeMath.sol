// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SafeMath {
    function add(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 result = a + b;
        require(result >= a, "Addition overflow"); 
        return result;
    }
    function sub(uint256 a, uint256 b) public pure returns (uint256) {
        require(b <= a, "Subtraction underflow"); 
        return a - b;
    }
}
