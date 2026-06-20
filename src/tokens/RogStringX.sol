// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RogStringX is ERC20, Ownable {

    error ZeroAmount();

    uint public constant MAX_SUPPLY = 10000000 * 10 ** 18;

    constructor() ERC20("RogStringX", "RSX") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    /**@notice Mints new tokens to the specified address. Only the owner can call this function.
     * @param to The address to which the tokens will be minted.
     * @param amount The amount of tokens to mint. Must be greater than zero.
     * @dev Reverts with ZeroAmount if the amount is zero.
     */

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY,"Exceeds max supply");
        if (amount == 0) {
            revert ZeroAmount();
        }
        _mint(to, amount);
    }
}
