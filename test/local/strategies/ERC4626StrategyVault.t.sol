// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {VaultMock} from "@test/mocks/VaultMock.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Auth, SIZE_VAULT_ROLE} from "@src/Auth.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";
import {BaseVault} from "@src/BaseVault.sol";

contract ERC4626StrategyVaultTest is BaseTest {
    uint256 initialBalance;
    uint256 initialTotalAssets;

    function setUp() public override {
        super.setUp();
        initialTotalAssets = erc4626StrategyVault.totalAssets();
        initialBalance = erc20Asset.balanceOf(address(erc4626Vault));
    }

    function test_ERC4626StrategyVault_deposit_balanceOf_totalAssets() public {
        uint256 amount = 100e6;
        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), amount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(amount, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), amount);
        assertEq(erc4626StrategyVault.totalAssets(), initialTotalAssets + amount);
        assertEq(erc20Asset.balanceOf(address(erc4626Vault)), initialBalance + amount);
        assertEq(erc20Asset.balanceOf(alice), 0);
    }

    function test_ERC4626StrategyVault_deposit_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), depositAmount);
        assertEq(erc4626StrategyVault.totalAssets(), initialTotalAssets + depositAmount);
        assertEq(erc20Asset.balanceOf(address(erc4626Vault)), initialBalance + depositAmount);
        assertEq(erc20Asset.balanceOf(alice), 0);

        uint256 withdrawAmount = 30e6;
        vm.prank(alice);
        erc4626StrategyVault.withdraw(withdrawAmount, alice, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), depositAmount - withdrawAmount);
        assertEq(erc4626StrategyVault.totalAssets(), initialTotalAssets + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(address(erc4626Vault)), initialBalance + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(alice), withdrawAmount);
    }

    function test_ERC4626StrategyVault_deposit_transferAssets_does_not_change_balanceOf() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        uint256 pullAmount = 30e6;
        vm.prank(address(sizeMetaVault));
        erc4626StrategyVault.transferAssets(bob, pullAmount);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(erc4626Vault)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(bob), pullAmount);
    }

    function test_ERC4626StrategyVault_deposit_transferAssets_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        uint256 pullAmount = 30e6;
        vm.prank(address(sizeMetaVault));
        erc4626StrategyVault.transferAssets(bob, pullAmount);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(erc4626Vault)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(bob), pullAmount);

        uint256 previewRedeemAssets = erc4626StrategyVault.previewRedeem(shares);

        vm.prank(alice);
        erc4626StrategyVault.redeem(shares, alice, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), 0);
        assertEq(erc20Asset.balanceOf(alice), previewRedeemAssets);
    }

    function test_ERC4626StrategyVault_deposit_donate_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(erc4626Vault), donation);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.balanceOf(bob), 0);

        uint256 previewRedeemAssets = erc4626StrategyVault.previewRedeem(shares);

        vm.prank(alice);
        erc4626StrategyVault.withdraw(previewRedeemAssets, alice, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), 0);
        assertEq(erc20Asset.balanceOf(alice), previewRedeemAssets);
    }

    function test_ERC4626StrategyVault_deposit_donate_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(erc4626Vault), donation);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.balanceOf(bob), 0);

        uint256 previewRedeemAssets = erc4626StrategyVault.previewRedeem(shares);

        vm.prank(alice);
        erc4626StrategyVault.redeem(shares, alice, alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), 0);
        assertEq(erc20Asset.balanceOf(alice), previewRedeemAssets);
    }

    /// Test for improper initailizaton ///

    function test_DeployErc4626StrategyVault_with_zero_address_auth_must_revert() public {
        VaultMock vaultMock = new VaultMock(alice, erc20Asset, "VAULTMOCK", "VM");
        _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

        address ERC4626StrategyVaultImplementation = address(new ERC4626StrategyVault());

        vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
        vm.prank(alice);
        ERC4626StrategyVault(
            payable(
                new ERC1967Proxy(
                    ERC4626StrategyVaultImplementation,
                    abi.encodeWithSelector(
                        ERC4626StrategyVault.initialize.selector,
                        Auth(address(0)),
                        erc20Asset,
                        "VAULT",
                        "VAULT",
                        FIRST_DEPOSIT_AMOUNT,
                        vaultMock
                    )
                )
            )
        );
    }

    function test_DeployErc4626StrategyVault_with_zero_first_amount_to_deposit_must_revert() public {
        VaultMock vaultMock = new VaultMock(alice, erc20Asset, "VAULTMOCK", "VM");

        address AuthImplementation = address(new Auth());
        Auth auth =
            Auth(payable(new ERC1967Proxy(AuthImplementation, abi.encodeWithSelector(Auth.initialize.selector, bob))));

        address ERC4626StrategyVaultImplementation = address(new ERC4626StrategyVault());

        vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAmount.selector));
        vm.prank(alice);
        ERC4626StrategyVault(
            payable(
                new ERC1967Proxy(
                    ERC4626StrategyVaultImplementation,
                    abi.encodeWithSelector(
                        ERC4626StrategyVault.initialize.selector, auth, erc20Asset, "VAULT", "VAULT", 0, vaultMock
                    )
                )
            )
        );
    }

    function test_DeployErc4626StrategyVault_with_zero_address_vault_must_revert() public {
        _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

        address AuthImplementation = address(new Auth());
        Auth auth =
            Auth(payable(new ERC1967Proxy(AuthImplementation, abi.encodeWithSelector(Auth.initialize.selector, bob))));

        _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

        address ERC4626StrategyVaultImplementation = address(new ERC4626StrategyVault());

        vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
        vm.prank(alice);
        ERC4626StrategyVault(
            payable(
                new ERC1967Proxy(
                    ERC4626StrategyVaultImplementation,
                    abi.encodeWithSelector(
                        ERC4626StrategyVault.initialize.selector,
                        auth,
                        erc20Asset,
                        "VAULT",
                        "VAULT",
                        FIRST_DEPOSIT_AMOUNT,
                        VaultMock(address(0))
                    )
                )
            )
        );
    }

    function test_ERC4626StrategyVault_maxDeposit() public {
        address dummy = makeAddr("dummy");
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        assertEq(
            erc4626StrategyVault.vault().maxDeposit(address(erc4626StrategyVault)),
            erc4626StrategyVault.maxDeposit(dummy)
        );

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(erc4626Vault), donation);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.balanceOf(bob), 0);

        assertEq(
            erc4626StrategyVault.vault().maxDeposit(address(erc4626StrategyVault)),
            erc4626StrategyVault.maxDeposit(dummy)
        );
    }

    function test_ERC4626StrategyVault_maxMint() public {
        address dummy = makeAddr("dummy");
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        assertEq(
            erc4626StrategyVault.vault().maxMint(address(erc4626StrategyVault)), erc4626StrategyVault.maxMint(dummy)
        );

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(erc4626Vault), donation);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);
        assertEq(erc4626StrategyVault.balanceOf(bob), 0);

        assertEq(
            erc4626StrategyVault.vault().maxMint(address(erc4626StrategyVault)), erc4626StrategyVault.maxMint(dummy)
        );
    }

    function test_ERC4626StrategyVault_maxWithdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        assertEq(erc4626StrategyVault.convertToAssets(shares), erc4626StrategyVault.maxWithdraw(alice));

        uint256 depositAmount2 = 50e6;
        _mint(erc20Asset, bob, depositAmount2);
        _approve(bob, erc20Asset, address(erc4626StrategyVault), depositAmount2);
        vm.prank(bob);
        erc4626StrategyVault.deposit(depositAmount2, bob);
        uint256 shares2 = erc4626StrategyVault.balanceOf(bob);
        assertEq(erc4626StrategyVault.balanceOf(bob), shares2);

        assertEq(erc4626StrategyVault.convertToAssets(shares2), erc4626StrategyVault.maxWithdraw(bob));

        assertEq(
            erc4626StrategyVault.maxWithdraw(bob) + erc4626StrategyVault.maxWithdraw(alice)
                + erc4626StrategyVault.maxWithdraw(address(erc4626StrategyVault)),
            erc4626StrategyVault.vault().maxWithdraw(address(erc4626StrategyVault))
        );

        uint256 burnAmount = (depositAmount + depositAmount2) / 2;
        _burn(erc20Asset, address(erc4626StrategyVault.vault()), burnAmount);

        uint256 prevAliceMaxWithdraw = erc4626StrategyVault.maxWithdraw(alice);
        uint256 prevBobMaxWithdraw = erc4626StrategyVault.maxWithdraw(bob);

        assertEq(erc4626StrategyVault.convertToAssets(shares), prevAliceMaxWithdraw);
        assertEq(erc4626StrategyVault.convertToAssets(shares2), prevBobMaxWithdraw);

        _mint(erc20Asset, address(erc4626Vault), depositAmount);

        assertGt(erc4626StrategyVault.maxWithdraw(alice), prevAliceMaxWithdraw);
        assertGt(erc4626StrategyVault.maxWithdraw(bob), prevBobMaxWithdraw);

        assertApproxEqAbs(
            erc4626StrategyVault.maxWithdraw(alice) + erc4626StrategyVault.maxWithdraw(bob)
                + erc4626StrategyVault.maxWithdraw(address(erc4626StrategyVault)),
            erc4626StrategyVault.vault().maxWithdraw(address(erc4626StrategyVault)),
            10
        );
    }

    function test_ERC4626StrategyVault_maxRedeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(erc4626StrategyVault), depositAmount);
        vm.prank(alice);
        erc4626StrategyVault.deposit(depositAmount, alice);
        uint256 shares = erc4626StrategyVault.balanceOf(alice);
        assertEq(erc4626StrategyVault.balanceOf(alice), shares);

        assertEq(erc4626StrategyVault.balanceOf(alice), erc4626StrategyVault.maxRedeem(alice));

        uint256 depositAmount2 = 50e6;
        _mint(erc20Asset, bob, depositAmount2);
        _approve(bob, erc20Asset, address(erc4626StrategyVault), depositAmount2);
        vm.prank(bob);
        erc4626StrategyVault.deposit(depositAmount2, bob);
        uint256 shares2 = erc4626StrategyVault.balanceOf(bob);
        assertEq(erc4626StrategyVault.balanceOf(bob), shares2);

        assertEq(erc4626StrategyVault.balanceOf(bob), erc4626StrategyVault.maxRedeem(bob));

        uint256 burnAmount = (depositAmount + depositAmount2) / 2;
        _burn(erc20Asset, address(erc4626StrategyVault.vault()), burnAmount);

        assertEq(erc4626StrategyVault.balanceOf(alice), erc4626StrategyVault.maxRedeem(alice));
        assertEq(erc4626StrategyVault.balanceOf(bob), erc4626StrategyVault.maxRedeem(bob));

        assertEq(
            erc4626StrategyVault.maxRedeem(bob) + erc4626StrategyVault.maxRedeem(alice)
                + erc4626StrategyVault.maxRedeem(address(erc4626StrategyVault)),
            erc4626StrategyVault.vault().maxRedeem(address(erc4626StrategyVault))
        );
    }
}
