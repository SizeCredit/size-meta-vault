// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseVault} from "@src/BaseVault.sol";
import {SizeMetaVaultHelper} from "@test/property/crytic/NewPropertyContracts/SizeMetaVaultHelper.t.sol";
import {IStrategy} from "@src/strategies/IStrategy.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract SizeMetaVaultPropes is SizeMetaVaultHelper {
    function test_SizeMetaVault_rebalance_property_testing(
        uint256 depositAmount,
        uint256 rebalanceAmount,
        uint256 indexFrom,
        uint256 indexTo
    ) public {
        indexFrom = _between(indexFrom, 0, 2);
        indexTo = _between(indexTo, 0, 2);
        while (indexFrom == indexTo) {
            uint256 counter = 0;
            indexTo = _between(indexFrom + counter, 0, 2);
            counter++;
        }

        (address strategyFromAddress, address strategyToAddress) = _setTwoStrategiesInOrder(indexFrom, indexTo);

        assertEq(sizeMetaVault.strategiesCount(), 2, "failed to set only two strategies");

        IStrategy strategyFrom = IStrategy(strategyFromAddress);
        IStrategy strategyTo = IStrategy(strategyToAddress);

        depositAmount = _between(depositAmount, 0, type(uint256).max - 1);

        uint256 balanceOfUserBefore = asset.balanceOf(address(user));
        asset.mint(address(user), depositAmount);
        asset.approve(address(sizeMetaVault), depositAmount);

        assert(asset.balanceOf(address(user)) == (depositAmount + balanceOfUserBefore));

        user.proxy(
            address(sizeMetaVault),
            abi.encodeWithSelector(ERC4626Upgradeable.deposit.selector, depositAmount, address(user))
        );

        uint256 assetStrategyFromBefore = strategyFrom.totalAssets();
        uint256 assetStrategyToBefore = strategyTo.totalAssets();

        rebalanceAmount =
            _between(rebalanceAmount, 0, strategyFrom.totalAssets() - BaseVault(address(strategyFrom)).deadAssets());

        strategist.proxy(
            address(sizeMetaVault),
            abi.encodeWithSelector(SizeMetaVault.rebalance.selector, strategyFrom, strategyTo, rebalanceAmount)
        );

        assertEq(strategyFrom.totalAssets(), assetStrategyFromBefore - rebalanceAmount, "check rebalance fucntion");
        assertEq(strategyTo.totalAssets(), assetStrategyToBefore + rebalanceAmount, "check rebalance fucntion");
    }
}
