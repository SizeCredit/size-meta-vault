// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Auth} from "@src/Auth.sol";

contract ForkTest is BaseTest {
    IERC20Metadata asset;
    uint256 firstDepositAmount;

    function setUp() public virtual override {
        vm.createSelectFork("base");

        asset = IERC20Metadata(vm.envAddress("ASSET"));
        firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
        auth = Auth(address(new ERC1967Proxy(address(new Auth()), abi.encodeCall(Auth.initialize, (admin)))));
    }
}
