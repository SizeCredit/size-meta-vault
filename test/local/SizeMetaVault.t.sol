// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {IStrategy} from "@src/strategies/IStrategy.sol";

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

    function test_SizeMetaVault_AddStrategyValidation() public {
        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.NULL_ADDRESS.selector));
        sizeMetaVault.addStrategy(address(0));
    }

    function test_SizeMetaVault_RemoveStrategyValidation() public {
        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.NULL_ADDRESS.selector));
        sizeMetaVault.removeStrategy(address(0));
    }

    function test_SizeMetaVault_SetStrategiesValidation() public {
        address[] memory strategiesWithZero = new address[](2);
        strategiesWithZero[0] = address(0);
        strategiesWithZero[1] = address(0xDEAD);

        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.NULL_ADDRESS.selector));
        sizeMetaVault.setStrategies(strategiesWithZero);
    }

    function test_SizeMetaVault_RebalanceValidation() public {
        uint256 cashAssetsBefore = cashStrategyVault.totalAssets();
        uint256 erc4626AssetsBefore = erc4626StrategyVault.totalAssets();
        uint256 cashStrategyDeadAssets = cashStrategyVault.deadAssets();

        uint256 amount = 5e6;

        // validate strategyFrom
        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(1)));
        sizeMetaVault.rebalance(IStrategy(address(1)), erc4626StrategyVault, amount);

        // validate strategyTo
        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(1)));
        sizeMetaVault.rebalance(cashStrategyVault, IStrategy(address(1)), amount);

        // validate amount 0
        vm.prank(strategist);
        vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.NULL_AMOUNT.selector));
        sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, 0);

        // validate amount > balance
        amount = 50e6;
        assertLt(cashAssetsBefore, amount);

        vm.prank(strategist);
        vm.expectRevert(
            abi.encodeWithSelector(
                SizeMetaVault.InsufficientAssets.selector, cashAssetsBefore, cashStrategyDeadAssets, amount
            )
        );
        sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount);
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
}
