// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {AaveStrategyVaultForkTest} from "@test/fork/strategies/AaveStrategyVault.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SizeMetaVaultForkTest is AaveStrategyVaultForkTest {
    using SafeERC20 for IERC20Metadata;

    function setUp() public virtual override {
        super.setUp();

        _mint(asset, address(this), FIRST_DEPOSIT_AMOUNT);

        address[] memory initialStrategies = new address[](1);
        initialStrategies[0] = address(aaveStrategyVault);

        address implementation = address(new SizeMetaVault());
        bytes memory initializationData = abi.encodeCall(
            SizeMetaVault.initialize,
            (
                auth,
                IERC20Metadata(address(asset)),
                string.concat("Size ", asset.name(), " Meta Vault"),
                string.concat("size", asset.symbol()),
                FIRST_DEPOSIT_AMOUNT,
                initialStrategies
            )
        );
        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
        bytes32 salt = keccak256(initializationData);
        sizeMetaVault = SizeMetaVault(Create2.computeAddress(salt, keccak256(creationCode)));
        asset.forceApprove(address(sizeMetaVault), FIRST_DEPOSIT_AMOUNT);
        Create2.deploy(
            0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData))
        );
    }

    function test_SizeMetaVault_Fork_deposit_withdraw_with_interest() public {
        uint256 amount = 10 * 10 ** asset.decimals();

        _mint(asset, alice, amount);
        _approve(alice, asset, address(sizeMetaVault), amount);

        vm.startPrank(alice);

        sizeMetaVault.deposit(amount, alice);

        vm.warp(block.timestamp + 1 weeks);

        uint256 redeemedAssets = sizeMetaVault.redeem(sizeMetaVault.balanceOf(alice), alice, alice);

        assertGt(redeemedAssets, amount);
    }
}
