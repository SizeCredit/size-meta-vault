// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseVault} from "@src/BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Auth, STRATEGIST_ROLE} from "@src/Auth.sol";
import {IStrategy} from "@src/strategies/IStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SizeMetaVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Meta vault that distributes assets across multiple strategies
/// @dev Extends BaseVault to manage multiple strategy vaults for asset allocation
contract SizeMetaVault is BaseVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    EnumerableSet.AddressSet internal strategies;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event Rebalance(address indexed strategyFrom, address indexed strategyTo, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidStrategy(address strategy);
    error CannotDepositToStrategies(uint256 assets, uint256 shares, uint256 remainingAssets);
    error CannotWithdrawFromStrategies(uint256 assets, uint256 shares, uint256 missingAssets);
    error InsufficientAssets(uint256 totalAssets, uint256 deadAssets, uint256 amount);
    error NULL_ADDRESS();
    error NULL_AMOUNT();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR / INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the SizeMetaVault with strategies
    /// @dev Adds all provided strategies and calls parent initialization
    function initialize(
        Auth auth_,
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 firstDepositAmount,
        address[] memory strategies_
    ) public virtual initializer {
        for (uint256 i = 0; i < strategies_.length; i++) {
            _addStrategy(strategies_[i]);
        }

        super.initialize(auth_, asset_, name_, symbol_, firstDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the maximum amount that can be deposited
    function maxDeposit(address) public view override returns (uint256) {
        uint256 length = strategies.length();
        uint256 max = 0;
        for (uint256 i = 0; i < length; i++) {
            IStrategy strategy = IStrategy(strategies.at(i));
            uint256 strategyMaxDeposit = strategy.maxDeposit(address(this));
            max = Math.saturatingAdd(max, strategyMaxDeposit);
        }
        return max;
    }

    /// @notice Returns the maximum number of shares that can be minted
    /// @dev Converts the max deposit amount to shares
    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxDepositAmount = maxDeposit(receiver);
        return maxDepositAmount == type(uint256).max ? type(uint256).max : convertToShares(maxDepositAmount);
    }

    /// @notice Returns the maximum amount that can be withdrawn by an owner
    /// @dev Limited by both owner's balance and total withdrawable assets
    function maxWithdraw(address owner) public view override returns (uint256) {
        return Math.min(_convertToAssets(balanceOf(owner), Math.Rounding.Floor), _maxWithdraw());
    }

    /// @notice Returns the maximum number of shares that can be redeemed
    /// @dev Limited by both owner's balance and total withdrawable assets
    function maxRedeem(address owner) public view override returns (uint256) {
        return Math.min(balanceOf(owner), _convertToShares(_maxWithdraw(), Math.Rounding.Floor));
    }

    /// @notice Returns the total assets managed by the vault
    /// @dev Sums the total assets across all strategies
    /// @return The total assets under management
    function totalAssets() public view virtual override returns (uint256) {
        uint256 length = strategies.length();
        uint256 total = 0;
        for (uint256 i = 0; i < length; i++) {
            IStrategy strategy = IStrategy(strategies.at(i));
            total += strategy.totalAssets();
        }
        return total;
    }

    /// @notice Deposits assets to strategies in order
    /// @dev Tries to deposit to strategies sequentially, reverts if not all assets can be deposited
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (_isInitializing()) {
            // first deposit
            shares = assets;
        }

        super._deposit(caller, receiver, assets, shares);

        uint256 assetsToDeposit = assets;

        uint256 length = strategies.length();
        for (uint256 i = 0; i < length; i++) {
            IStrategy strategy = IStrategy(strategies.at(i));

            uint256 strategyMaxDeposit = strategy.maxDeposit(address(this));
            uint256 depositAmount = Math.min(assetsToDeposit, strategyMaxDeposit);
            IERC20(asset()).forceApprove(address(strategy), depositAmount);
            try strategy.deposit(depositAmount, address(this)) {
                assetsToDeposit -= depositAmount;
            } catch {
                IERC20(asset()).forceApprove(address(strategy), 0);
            }

            if (assetsToDeposit == 0) {
                break;
            }
        }
        if (assetsToDeposit > 0) {
            revert CannotDepositToStrategies(assets, shares, assetsToDeposit);
        }
    }

    /// @notice Withdraws assets from strategies in order
    /// @dev Tries to withdraw from strategies sequentially, reverts if not enough assets available
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint256 assetsToWithdraw = assets;

        uint256 length = strategies.length();

        for (uint256 i = 0; i < length; i++) {
            IStrategy strategy = IStrategy(strategies.at(i));

            uint256 strategyMaxWithdraw = strategy.maxWithdraw(address(this));
            uint256 withdrawAmount = Math.min(assetsToWithdraw, strategyMaxWithdraw);
            try strategy.withdraw(withdrawAmount, address(this), address(this)) {
                assetsToWithdraw -= withdrawAmount;
            } catch {}

            if (assetsToWithdraw == 0) {
                break;
            }
        }
        if (assetsToWithdraw > 0) {
            revert CannotWithdrawFromStrategies(assets, shares, assetsToWithdraw);
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                              STRATEGST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Replaces all current strategies with new ones
    /// @dev Removes all existing strategies and adds the new ones
    function setStrategies(address[] calldata strategies_) external whenNotPaused onlyAuth(STRATEGIST_ROLE) {
        uint256 length = strategies.length();
        for (uint256 i = 0; i < length; i++) {
            _removeStrategy(strategies.at(i));
        }
        for (uint256 i = 0; i < strategies_.length; i++) {
            _addStrategy(strategies_[i]);
        }
    }

    /// @notice Adds a new strategy to the vault
    /// @dev Only callable by addresses with STRATEGIST_ROLE
    function addStrategy(address strategy) external whenNotPaused onlyAuth(STRATEGIST_ROLE) {
        _addStrategy(strategy);
    }

    /// @notice Removes a strategy from the vault
    /// @dev Only callable by addresses with STRATEGIST_ROLE
    function removeStrategy(address strategy) external whenNotPaused onlyAuth(STRATEGIST_ROLE) {
        _removeStrategy(strategy);
    }

    /// @notice Rebalances assets between two strategies
    /// @dev Transfers assets from one strategy to another and skims the destination
    function rebalance(IStrategy strategyFrom, IStrategy strategyTo, uint256 amount)
        external
        whenNotPaused
        onlyAuth(STRATEGIST_ROLE)
    {
        if (!strategies.contains(address(strategyFrom))) {
            revert InvalidStrategy(address(strategyFrom));
        }
        if (!strategies.contains(address(strategyTo))) {
            revert InvalidStrategy(address(strategyTo));
        }
        if (amount == 0) {
            revert NULL_AMOUNT();
        }
        if (amount + BaseVault(address(strategyFrom)).deadAssets() > strategyFrom.totalAssets()) {
            revert InsufficientAssets(strategyFrom.totalAssets(), BaseVault(address(strategyFrom)).deadAssets(), amount);
        }

        strategyFrom.transferAssets(address(strategyTo), amount);
        strategyTo.skim();

        emit Rebalance(address(strategyFrom), address(strategyTo), amount);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal function to add a strategy
    /// @dev Emits StrategyAdded event if the strategy was successfully added
    function _addStrategy(address strategy) private {
        if (address(strategy) == address(0)) {
            revert NULL_ADDRESS();
        }
        bool added = strategies.add(strategy);
        if (added) {
            emit StrategyAdded(strategy);
        }
    }

    /// @notice Internal function to remove a strategy
    /// @dev Emits StrategyRemoved event if the strategy was successfully removed
    function _removeStrategy(address strategy) private {
        if (address(strategy) == address(0)) {
            revert NULL_ADDRESS();
        }
        bool removed = strategies.remove(strategy);
        if (removed) {
            emit StrategyRemoved(strategy);
        }
    }

    /// @notice Internal function to calculate maximum withdrawable amount
    /// @dev Sums the max withdraw amounts across all strategies
    /// @return The total maximum withdrawable amount
    function _maxWithdraw() private view returns (uint256) {
        uint256 length = strategies.length();
        uint256 max = 0;
        for (uint256 i = 0; i < length; i++) {
            IStrategy strategy = IStrategy(strategies.at(i));
            uint256 strategyMaxWithdraw = strategy.maxWithdraw(address(this));
            max = Math.saturatingAdd(max, strategyMaxWithdraw);
        }
        return max;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the number of strategies in the vault
    /// @return The count of active strategies
    function strategiesCount() public view returns (uint256) {
        return strategies.length();
    }

    /// @notice Returns all strategy addresses
    /// @return Array of all strategy addresses
    function getStrategies() public view returns (address[] memory) {
        return strategies.values();
    }

    /// @notice Returns the strategy address at a specific index
    /// @return The strategy address at the given index
    function getStrategy(uint256 index) public view returns (address) {
        return strategies.at(index);
    }
}
