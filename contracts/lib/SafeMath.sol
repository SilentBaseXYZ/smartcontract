// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 result = a + b;
        require(result >= a, "Addition overflow"); 
        return result;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Subtraction underflow"); 
        return a - b;
    }

    function mul(uint256 price, uint256 quantity) internal pure returns (uint256) {
        uint256 result = divideAndRound((price * quantity), 1 ether);
        return result;
    }

    function divideAndRound(uint256 a, uint256 b) internal  pure returns (uint256) {
        return (a + (b / 2)) / b;
    }
}
