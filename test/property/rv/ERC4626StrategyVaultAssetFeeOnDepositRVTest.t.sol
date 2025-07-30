// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Test} from "@rv/ercx/src/ERC4626/Light/ERC4626Test.sol";
import {Setup} from "@test/Setup.t.sol";

contract ERC4626StrategyVaultAssetFeeOnDepositRVTest is ERC4626Test, Setup {
    function setUp() public {
        deploy(address(this));
        ERC4626Test.init(address(erc4626StrategyVaultAssetFeeOnDeposit));
    }
}
