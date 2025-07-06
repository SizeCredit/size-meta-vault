// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

contract SizeMetaVaultTest is BaseTest {
    function test_SizeMetaVault_initialize() public view {
        assertEq(address(sizeMetaVault.asset()), address(erc20Asset));
        assertEq(sizeMetaVault.name(), string.concat("Size ", erc20Asset.name(), " Vault"));
        assertEq(sizeMetaVault.symbol(), string.concat("size", erc20Asset.symbol()));
        assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
        assertEq(sizeMetaVault.totalSupply(), sizeMetaVault.strategiesCount() * FIRST_DEPOSIT_AMOUNT + 1);
        assertEq(sizeMetaVault.balanceOf(address(this)), 0);
        assertEq(sizeMetaVault.allowance(address(this), address(this)), 0);
        assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
        assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
    }

    function test_SizeMetaVault_rebalance() public {
        uint256 cashAssetsBefore = cashStrategyVault.totalAssets();
        uint256 erc4626AssetsBefore = erc4626StrategyVault.totalAssets();
        uint256 cashStrategyDeadAssets = cashStrategyVault.deadAssets();

        uint256 amount = 50e6;
        assertLt(cashAssetsBefore, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                SizeMetaVault.InsufficientAssets.selector, cashAssetsBefore, cashStrategyDeadAssets, amount
            )
        );
        vm.prank(strategist);
        sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount);

        vm.prank(strategist);
        sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, 5e6);
        assertEq(cashStrategyVault.totalAssets(), cashAssetsBefore - 5e6);
        assertEq(erc4626StrategyVault.totalAssets(), erc4626AssetsBefore + 5e6);
    }

    function test_SizeMetaVault_setStrategies() public {
        address[] memory strategies = new address[](3);
        strategies[0] = makeAddr("strategy1");
        strategies[1] = makeAddr("strategy2");
        strategies[2] = makeAddr("strategy3");

        vm.prank(strategist);
        sizeMetaVault.setStrategies(strategies);

        assertEq(sizeMetaVault.getStrategy(0), strategies[0]);
        assertEq(sizeMetaVault.getStrategy(1), strategies[1]);
        assertEq(sizeMetaVault.getStrategy(2), strategies[2]);
    }
}
