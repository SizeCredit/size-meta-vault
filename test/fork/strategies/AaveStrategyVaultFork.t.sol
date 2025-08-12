// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ForkTest} from "@test/fork/ForkTest.t.sol";
import {IPoolConfigurator} from "@aave/contracts/interfaces/IPoolConfigurator.sol";
import {ReserveConfiguration} from "@aave/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";

contract AaveStrategyVaultForkTest is ForkTest {
    using SafeERC20 for IERC20Metadata;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IPool public aavePool = IPool(AAVE_POOL_BASE_MAINNET);
    IPoolConfigurator public aavePoolConfigurator = IPoolConfigurator(AAVE_POOL_CONFIGURATOR_BASE_MAINNET);
    address public aavePoolAdmin = AAVE_POOL_ADMIN_BASE_MAINNET;

    function setUp() public virtual override {
        super.setUp();

        // can choose a better value
        FIRST_DEPOSIT_AMOUNT = 10e6;

        _mint(erc20Asset, address(this), FIRST_DEPOSIT_AMOUNT);

        address implementation = address(new AaveStrategyVault());
        bytes memory initializationData = abi.encodeCall(
            AaveStrategyVault.initialize,
            (
                auth,
                IERC20(address(erc20Asset)),
                string.concat("Aave ", erc20Asset.name(), " Strategy"),
                string.concat("aave", erc20Asset.symbol()),
                address(this),
                FIRST_DEPOSIT_AMOUNT,
                aavePool
            )
        );
        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
        bytes32 salt = keccak256(initializationData);
        aaveStrategyVault = AaveStrategyVault(create2Deployer.computeAddress(salt, keccak256(creationCode)));
        erc20Asset.forceApprove(address(aaveStrategyVault), FIRST_DEPOSIT_AMOUNT);
        create2Deployer.deploy(
            0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData))
        );
    }

    function testFork_AaveStrategyVault_initialize_with_zero_address_pool_must_revert() public {
        _mint(erc20Asset, address(this), FIRST_DEPOSIT_AMOUNT);

        address implementation = address(new AaveStrategyVault());
        bytes memory initializationData = abi.encodeCall(
            AaveStrategyVault.initialize,
            (
                auth,
                IERC20(address(erc20Asset)),
                string.concat("Aave ", erc20Asset.name(), " Strategy"),
                string.concat("aave", erc20Asset.symbol()),
                address(this),
                FIRST_DEPOSIT_AMOUNT,
                IPool(address(0))
            )
        );
        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
        bytes32 salt = keccak256(initializationData);
        aaveStrategyVault = AaveStrategyVault(create2Deployer.computeAddress(salt, keccak256(creationCode)));
        erc20Asset.forceApprove(address(aaveStrategyVault), FIRST_DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
        create2Deployer.deploy(
            0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData))
        );
    }

    // skip test_AaveStrategyVault_maxDeposit_getActive_false_must_return_zero, as we need to have no suppliers
    // check https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/PoolConfigurator.sol#L199

    function testFork_AaveStrategyVault_maxDeposit_if_frozen_must_return_zero() public {
        vm.prank(aavePoolAdmin);
        aavePoolConfigurator.setReserveFreeze(address(erc20Asset), true);

        assertEq(aavePool.getConfiguration(address(erc20Asset)).getFrozen(), true);

        uint256 returnValue = aaveStrategyVault.maxDeposit(address(this));

        assertEq(returnValue, 0);
    }

    function testFork_AaveStrategyVault_maxDeposit_maxWithdraw_maxRedeen_if_posed_must_return_zero() public {
        vm.prank(aavePoolAdmin);
        aavePoolConfigurator.setReservePause(address(erc20Asset), true);

        assertEq(aavePool.getConfiguration(address(erc20Asset)).getPaused(), true);

        uint256 maxDepositReturnValue = aaveStrategyVault.maxDeposit(address(this));
        uint256 maxWithdrawReturnValue = aaveStrategyVault.maxWithdraw(address(this));
        uint256 maxRedeemReturnValue = aaveStrategyVault.maxRedeem(address(this));

        assertEq(maxDepositReturnValue, 0);
        assertEq(maxWithdrawReturnValue, 0);
        assertEq(maxRedeemReturnValue, 0);
    }

    function testFork_AaveStrategyVault_maxDeposit_if_no_supplyCap_returns_max_uint256() public {
        vm.prank(aavePoolAdmin);
        aavePoolConfigurator.setSupplyCap(address(erc20Asset), 0);

        assertEq(aavePool.getConfiguration(address(erc20Asset)).getSupplyCap(), 0);

        uint256 maxDepositReturnValue = aaveStrategyVault.maxDeposit(address(this));

        assertEq(maxDepositReturnValue, type(uint256).max);
    }

    function testFork_AaveStrategyVault_increase_assets_after_some_time() public {
        uint256 amount = 10 * 10 ** erc20Asset.decimals();

        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), amount);

        vm.startPrank(alice);

        aaveStrategyVault.deposit(amount, alice);

        vm.warp(block.timestamp + 1 weeks);

        uint256 redeemedAssets = aaveStrategyVault.redeem(aaveStrategyVault.balanceOf(alice), alice, alice);

        assertGt(redeemedAssets, amount);
    }
}
