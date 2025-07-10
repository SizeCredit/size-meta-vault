// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultMockDecMaxDeposit is ERC4626, Ownable {
    constructor(address _owner, IERC20 _asset, string memory _name, string memory _symbol)
        ERC4626(_asset)
        ERC20(_name, _symbol)
        Ownable(_owner)
    {}

    function maxWithdraw(address) public pure override returns (uint256) {
        return type(uint256).max;
    }
}
