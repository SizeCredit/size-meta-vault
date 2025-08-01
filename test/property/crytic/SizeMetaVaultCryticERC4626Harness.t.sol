// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CryticERC4626PropertyTests} from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
import {Setup} from "@test/Setup.t.sol";
import {hevm} from "@crytic/properties/contracts/util/Hevm.sol";
import {IBaseVault} from "@src/IBaseVault.sol";

contract SizeMetaVaultCryticERC4626Harness is CryticERC4626PropertyTests, Setup {
    constructor() {
        deploy(address(this));
        initialize(address(sizeMetaVault), address(asset), true);
    }

    function rebalance(address strategyFrom, address strategyTo, uint256 amount, uint256 maxSlippagePercent) public {
        hevm.prank(address(this));
        sizeMetaVault.rebalance(IBaseVault(strategyFrom), IBaseVault(strategyTo), amount, maxSlippagePercent);
    }
}
