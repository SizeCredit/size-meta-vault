// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {SizeMetaVaultScript} from "@script/SizeMetaVault.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CashStrategyVaultScript} from "@script/CashStrategyVault.s.sol";
import {CashStrategyVault} from "@src/strategies/CashStrategyVault.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";
import {CryticCashStrategyVaultMock} from "@test/mocks/CryticCashStrategyVaultMock.t.sol";
import {CryticAaveStrategyVaultMock} from "@test/mocks/CryticAaveStrategyVaultMock.t.sol";
import {CryticERC4626StrategyVaultMock} from "@test/mocks/CryticERC4626StrategyVaultMock.t.sol";
import {USDC} from "@test/mocks/USDC.t.sol";
import {Setup} from "@test/Setup.t.sol";
import {PoolMock} from "@test/mocks/PoolMock.t.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";
import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {VaultMock} from "@test/mocks/VaultMock.t.sol";
import {Auth, STRATEGIST_ROLE, SIZE_VAULT_ROLE} from "@src/Auth.sol";

contract BaseTest is Test, Setup {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal alice = address(0x10000);
    address internal bob = address(0x20000);
    address internal charlie = address(0x30000);
    address internal admin = address(0x40000);
    address internal strategist = address(0x50000);

    function setUp() public virtual {
        deploy(admin);

        vm.label(address(auth), "Auth");
        vm.label(address(sizeMetaVault), "SizeMetaVault");

        vm.label(address(cashStrategyVault), "CashStrategyVault");
        vm.label(address(aaveStrategyVault), "AaveStrategyVault");
        vm.label(address(erc4626StrategyVault), "ERC4626StrategyVault");

        vm.label(address(cryticCashStrategyVault), "CryticCashStrategyVault");
        vm.label(address(cryticAaveStrategyVault), "CryticAaveStrategyVault");
        vm.label(address(cryticERC4626StrategyVault), "CryticERC4626StrategyVault");

        vm.label(address(erc20Asset), "ERC20Asset");
        vm.label(address(pool), "Pool");
        vm.label(address(aToken), "AToken");
        vm.label(address(erc4626Vault), "ERC4626Vault");

        vm.label(address(alice), "alice");
        vm.label(address(bob), "bob");
        vm.label(address(charlie), "charlie");
        vm.label(address(admin), "admin");
        vm.label(address(strategist), "strategist");

        vm.label(address(this), "Test");
        vm.label(address(0), "address(0)");

        vm.prank(admin);
        auth.grantRole(STRATEGIST_ROLE, strategist);
        vm.prank(admin);
        auth.grantRole(SIZE_VAULT_ROLE, address(sizeMetaVault));
    }

    function _mint(IERC20Metadata _asset, address _to, uint256 _amount) internal {
        deal(address(_asset), _to, _amount);
    }

    function _burn(IERC20Metadata _asset, address _from, uint256 _amount) internal {
        vm.prank(USDC(address(_asset)).owner());
        USDC(address(_asset)).burn(_from, _amount);
    }

    function _approve(address _user, IERC20Metadata _asset, address _spender, uint256 _amount) internal {
        vm.prank(_user);
        _asset.approve(_spender, _amount);
    }

    function assertEq(uint256 _a, uint256 _b, uint256 _c) internal pure {
        assertEq(_a, _b);
        assertEq(_a, _c);
    }
}
