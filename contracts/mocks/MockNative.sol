// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockNative is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    }

    function mint(address to, uint256 amount) external payable {
        require(msg.value == amount, "Amount is not equal to msg.value");
        _mint(to, amount);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}