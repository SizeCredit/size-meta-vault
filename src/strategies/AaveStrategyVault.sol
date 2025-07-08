// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {BaseVault} from "@src/BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {WadRayMath} from "@aave/contracts/protocol/libraries/math/WadRayMath.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {Auth, SIZE_VAULT_ROLE} from "@src/Auth.sol";
import {IStrategy} from "@src/strategies/IStrategy.sol";

/// @title AaveStrategyVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A strategy that invests assets in Aave v3 lending pools
/// @dev Implements IStrategy interface for Aave v3 integration within the Size Meta Vault system
/// @dev Reference https://github.com/superform-xyz/super-vaults/blob/8bc1d1bd1579f6fb9a047802256ed3a2bf15f602/src/aave-v3/AaveV3ERC4626Reinvest.sol
contract AaveStrategyVault is BaseVault, IStrategy {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    IPool public pool;
    IAToken public aToken;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant DECIMALS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
    uint256 internal constant ACTIVE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;
    uint256 internal constant PAUSED_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF;
    uint256 internal constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal constant RESERVE_DECIMALS_START_BIT_POSITION = 48;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolSet(address indexed poolBefore, address indexed poolAfter);
    event ATokenSet(address indexed aTokenBefore, address indexed aTokenAfter);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR / INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the AaveStrategyVault with an Aave pool
    /// @dev Sets the Aave pool and retrieves the corresponding aToken address
    function initialize(
        Auth auth_,
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 firstDepositAmount,
        IPool pool_
    ) public virtual initializer {
        if (address(pool_) == address(0)) {
            revert NullAddress();
        }

        pool = pool_;
        aToken = IAToken(pool_.getReserveData(address(asset_)).aTokenAddress);

        emit PoolSet(address(0), address(pool_));
        emit ATokenSet(address(0), address(aToken));

        super.initialize(auth_, asset_, name_, symbol_, firstDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              SIZE VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers assets from this strategy to another address
    /// @dev Withdraws from Aave pool and transfers to the recipient
    function transferAssets(address to, uint256 amount)
        external
        override
        notPaused
        onlyAuth(SIZE_VAULT_ROLE)
        nonReentrant
    {
        pool.withdraw(asset(), amount, to);
        emit TransferAssets(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invests any idle assets sitting in this contract
    /// @dev Supplies any assets held by this contract to the Aave pool
    function skim() external override notPaused onlyAuth(SIZE_VAULT_ROLE) nonReentrant {
        uint256 assets = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).forceApprove(address(pool), assets);
        pool.supply(asset(), assets, address(this), 0);
        emit Skim();
    }

    /*//////////////////////////////////////////////////////////////
                              ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the maximum amount that can be deposited
    /// @dev Checks Aave reserve configuration and supply cap to determine max deposit
    /// @return The maximum deposit amount allowed by Aave
    function maxDeposit(address) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        // check if asset is paused
        uint256 configData = pool.getReserveData(asset()).configuration.data;
        if (!(_getActive(configData) && !_getFrozen(configData) && !_getPaused(configData))) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = _getSupplyCap(configData);
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint8 tokenDecimals = _getDecimals(configData);
        uint256 supplyCap = supplyCapInWholeTokens * 10 ** tokenDecimals;
        DataTypes.ReserveDataLegacy memory reserve = pool.getReserveData(asset());
        uint256 usedSupply =
            (aToken.scaledTotalSupply() + uint256(reserve.accruedToTreasury)).rayMul(reserve.liquidityIndex);

        if (usedSupply >= supplyCap) return 0;
        return supplyCap - usedSupply;
    }

    /// @notice Returns the maximum number of shares that can be minted
    /// @dev Converts the max deposit amount to shares
    function maxMint(address receiver) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    /// @notice Returns the maximum amount that can be withdrawn by an owner
    /// @dev Limited by both owner's balance and Aave pool liquidity
    function maxWithdraw(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        // check if asset is paused
        uint256 configData = pool.getReserveData(asset()).configuration.data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
            return 0;
        }

        uint256 cash = IERC20(asset()).balanceOf(address(aToken));
        uint256 assetsBalance = convertToAssets(balanceOf(owner));
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Returns the maximum number of shares that can be redeemed
    /// @dev Limited by both owner's balance and Aave pool liquidity
    function maxRedeem(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        // check if asset is paused
        uint256 configData = pool.getReserveData(asset()).configuration.data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
            return 0;
        }

        uint256 cash = IERC20(asset()).balanceOf(address(aToken));
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf(owner);
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// @notice Returns the total assets managed by this strategy
    /// @dev Returns the aToken balance since aTokens represent the underlying asset with accrued interest
    function totalAssets() public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        /// @notice aTokens use rebasing to accrue interest, so the total assets is just the aToken balance
        return aToken.balanceOf(address(this));
    }

    /// @notice Internal deposit function that supplies assets to Aave
    /// @dev Calls parent deposit then supplies the assets to the Aave pool
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        IERC20(asset()).forceApprove(address(pool), assets);
        pool.supply(asset(), assets, address(this), 0);
    }

    /// @notice Internal withdraw function that withdraws from Aave
    /// @dev Withdraws from the Aave pool then calls parent withdraw
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        pool.withdraw(asset(), assets, address(this));
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Extracts the decimals from Aave reserve configuration data
    /// @dev Uses bit manipulation to extract decimals from the configuration
    function _getDecimals(uint256 configData) internal pure returns (uint8) {
        return uint8((configData & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION);
    }

    /// @notice Checks if the Aave reserve is active
    /// @dev Uses bit manipulation to check the active flag
    function _getActive(uint256 configData) internal pure returns (bool) {
        return configData & ~ACTIVE_MASK != 0;
    }

    /// @notice Checks if the Aave reserve is frozen
    /// @dev Uses bit manipulation to check the frozen flag
    function _getFrozen(uint256 configData) internal pure returns (bool) {
        return configData & ~FROZEN_MASK != 0;
    }

    /// @notice Checks if the Aave reserve is paused
    /// @dev Uses bit manipulation to check the paused flag
    function _getPaused(uint256 configData) internal pure returns (bool) {
        return configData & ~PAUSED_MASK != 0;
    }

    /// @notice Extracts the supply cap from Aave reserve configuration data
    /// @dev Uses bit manipulation to extract the supply cap value
    function _getSupplyCap(uint256 configData) internal pure returns (uint256) {
        return (configData & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
    }
}
