// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

contract CashStrategyVaultTest is BaseTest {
    uint256 initialBalance;
    uint256 initialTotalAssets;

    function setUp() public override {
        super.setUp();
        initialTotalAssets = cashStrategyVault.totalAssets();
        initialBalance = erc20Asset.balanceOf(address(cashStrategyVault));
    }

    function test_CashStrategyVault_deposit_balanceOf_totalAssets() public {
        uint256 amount = 100e6;
        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(cashStrategyVault), amount);
        vm.prank(alice);
        cashStrategyVault.deposit(amount, alice);
        assertEq(cashStrategyVault.balanceOf(alice), amount);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + amount);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + amount);
        assertEq(erc20Asset.balanceOf(alice), 0);
    }

    function test_CashStrategyVault_deposit_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);
        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        assertEq(cashStrategyVault.balanceOf(alice), depositAmount);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount);
        assertEq(erc20Asset.balanceOf(alice), 0);

        uint256 withdrawAmount = 30e6;
        vm.prank(alice);
        cashStrategyVault.withdraw(withdrawAmount, alice, alice);
        assertEq(cashStrategyVault.balanceOf(alice), depositAmount - withdrawAmount);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(alice), withdrawAmount);
    }

    function test_CashStrategyVault_deposit_rebalance_does_not_change_balanceOf() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);
        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        uint256 shares = cashStrategyVault.balanceOf(alice);
        assertEq(cashStrategyVault.balanceOf(alice), shares);

        uint256 balanceBeforeRebalance = erc20Asset.balanceOf(address(aToken));

        uint256 pullAmount = 30e6;
        vm.prank(strategist);
        sizeMetaVault.rebalance(cashStrategyVault, aaveStrategyVault, pullAmount, 0);
        assertEq(cashStrategyVault.balanceOf(alice), shares);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), balanceBeforeRebalance + pullAmount);
    }

    function test_CashStrategyVault_deposit_rebalance_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);
        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        uint256 shares = cashStrategyVault.balanceOf(alice);
        assertEq(cashStrategyVault.balanceOf(alice), shares);

        uint256 balanceBeforeRebalance = erc20Asset.balanceOf(address(aToken));

        uint256 pullAmount = 30e6;
        vm.prank(strategist);
        sizeMetaVault.rebalance(cashStrategyVault, aaveStrategyVault, pullAmount, 0);
        assertEq(cashStrategyVault.balanceOf(alice), shares);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), balanceBeforeRebalance + pullAmount);

        vm.prank(alice);
        cashStrategyVault.redeem(shares, alice, alice);
        assertEq(cashStrategyVault.balanceOf(alice), 0);
        assertLe(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance);

        assertGe(erc20Asset.balanceOf(alice), depositAmount - pullAmount);
    }

    function test_CashStrategyVault_deposit_donate_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);
        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        uint256 shares = cashStrategyVault.balanceOf(alice);
        assertEq(cashStrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(cashStrategyVault), donation);
        assertEq(cashStrategyVault.balanceOf(alice), shares);
        assertEq(cashStrategyVault.balanceOf(bob), 0);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount + donation);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount + donation);

        uint256 previewRedeemAssets = cashStrategyVault.previewRedeem(shares);

        vm.prank(alice);
        cashStrategyVault.withdraw(previewRedeemAssets, alice, alice);
        assertEq(cashStrategyVault.balanceOf(alice), 0);
        assertGe(cashStrategyVault.totalAssets(), initialTotalAssets);
        assertGe(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance);
        assertEq(erc20Asset.balanceOf(alice), previewRedeemAssets);
    }

    function test_CashStrategyVault_deposit_donate_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);
        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        uint256 shares = cashStrategyVault.balanceOf(alice);
        assertEq(cashStrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(cashStrategyVault), donation);
        assertEq(cashStrategyVault.balanceOf(alice), shares);
        assertEq(cashStrategyVault.balanceOf(bob), 0);
        assertEq(cashStrategyVault.totalAssets(), initialTotalAssets + depositAmount + donation);
        assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + depositAmount + donation);

        vm.prank(alice);
        cashStrategyVault.redeem(shares, alice, alice);
        assertEq(cashStrategyVault.balanceOf(alice), 0);
        assertGe(cashStrategyVault.totalAssets(), initialTotalAssets + 1);
        assertGe(erc20Asset.balanceOf(address(cashStrategyVault)), initialBalance + 1);
        assertGe(erc20Asset.balanceOf(alice), depositAmount);
    }

    function test_CashStrategyVault_deposit_rebalance_all_reverts() public {
        // if user redeems shares when the vault has no assets
        // the user will be allowed to to this
        // user will burn 100% of shares for zero assets
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(cashStrategyVault), depositAmount);

        vm.prank(alice);
        cashStrategyVault.deposit(depositAmount, alice);
        uint256 shares = cashStrategyVault.balanceOf(alice);
        assertEq(cashStrategyVault.balanceOf(alice), shares);

        uint256 pullAmount = erc20Asset.balanceOf(address(cashStrategyVault));
        uint256 deadAssets = cashStrategyVault.deadAssets();

        vm.prank(strategist);
        vm.expectRevert(
            abi.encodeWithSelector(SizeMetaVault.InsufficientAssets.selector, pullAmount, deadAssets, pullAmount)
        );
        sizeMetaVault.rebalance(cashStrategyVault, aaveStrategyVault, pullAmount, 0);
    }
}
