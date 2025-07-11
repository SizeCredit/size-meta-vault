// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IStrategy} from "@src/strategies/IStrategy.sol";
import {BaseVault} from "@src/BaseVault.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {Setup} from "@test/Setup.t.sol";
import {CryticERC4626PropertyBase} from "@crytic/properties/contracts/ERC4626/util/ERC4626PropertyTestBase.sol";

import {User} from "@crytic/properties/contracts/util/User.sol";

contract SizeMetaVaultHelper is Setup, CryticERC4626PropertyBase {
    mapping(uint256 => address) indexToStrategy;

    bytes32 constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 constant SIZE_VAULT_ROLE = keccak256("SIZE_VAULT_ROLE");

    User user;
    User strategist;

    constructor() {
        deploy(address(this));
        initialize(address(sizeMetaVault), address(erc20Asset), false);
        _setStrategyMapping();

        user = new User();
        strategist = new User();

        auth.grantRole(STRATEGIST_ROLE, address(strategist));
        auth.grantRole(SIZE_VAULT_ROLE, address(sizeMetaVault));
    }

    // remove all strategies a stragtegies
    // get what is need to put
    // add only two
    // in specific order because the first strategy always get all the money
    // cash --> erc4626
    // erc --> cash
    // cahs --> aave
    // aave --> cash
    // erc --> aave
    // aave --> erc

    function _setStrategyMapping() internal {
        indexToStrategy[0] = sizeMetaVault.getStrategy(0);
        indexToStrategy[1] = sizeMetaVault.getStrategy(1);
        indexToStrategy[2] = sizeMetaVault.getStrategy(2);
    }

    // this is import to ensure which strategy is going to be the sender of assets
    // which strategy is going to be the receiver bcz based on the deploy
    // CashVaultStratey will always be the first one so rebalnce will only take place from
    // cash into other vault strategies
    function _setTwoStrategiesInOrder(uint256 indexFrom, uint256 indexTo)
        internal
        returns (address strategyFrom, address strategyTo)
    {
        strategyFrom = indexToStrategy[indexFrom];
        strategyTo = indexToStrategy[indexTo];

        address[] memory newStrategies = new address[](2);
        newStrategies[0] = strategyFrom;
        newStrategies[1] = strategyTo;

        strategist.proxy(
            address(sizeMetaVault), abi.encodeWithSelector(SizeMetaVault.setStrategies.selector, newStrategies)
        );
        sizeMetaVault.setStrategies(newStrategies);

        return (strategyFrom, strategyTo);
    }

    function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
        return lower + (val % (upper - lower + 1));
    }
}
