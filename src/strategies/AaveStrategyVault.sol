// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BaseVault} from "@src/BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {WadRayMath} from "@aave/contracts/protocol/libraries/math/WadRayMath.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {Auth} from "@src/utils/Auth.sol";
import {ReserveConfiguration} from "@aave/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title AaveStrategyVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A strategy that invests assets in Aave v3 lending pools
/// @dev Extends BaseVault for Aave v3 integration within the Size Meta Vault system
/// @dev Reference https://github.com/superform-xyz/super-vaults/blob/8bc1d1bd1579f6fb9a047802256ed3a2bf15f602/src/aave-v3/AaveV3ERC4626Reinvest.sol
contract AaveStrategyVault is BaseVault {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    IPool public pool;
    IAToken public aToken;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolSet(address indexed pool);
    event ATokenSet(address indexed aToken);

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
        address fundingAccount,
        uint256 firstDepositAmount,
        IPool pool_
    ) public virtual initializer {
        if (address(pool_) == address(0)) {
            revert NullAddress();
        }
        if (address(pool_.getReserveData(address(asset_)).aTokenAddress) == address(0)) {
            revert InvalidAsset(address(asset_));
        }

        pool = pool_;
        emit PoolSet(address(pool_));
        aToken = IAToken(pool_.getReserveData(address(asset_)).aTokenAddress);
        emit ATokenSet(address(aToken));

        super.initialize(auth_, asset_, name_, symbol_, fundingAccount, firstDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invests any idle assets sitting in this contract
    /// @dev Supplies any assets held by this contract to the Aave pool
    function skim() external override nonReentrant notPaused {
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
    /// @dev Updates Superform implementation to comply with https://github.com/aave-dao/aave-v3-origin/blob/v3.4.0/src/contracts/protocol/libraries/logic/ValidationLogic.sol#L79-L85
    /// @return The maximum deposit amount allowed by Aave
    function maxDeposit(address receiver) public view override(BaseVault) returns (uint256) {
        // check if asset is paused
        DataTypes.ReserveConfigurationMap memory config = pool.getReserveData(asset()).configuration;
        if (!(config.getActive() && !config.getFrozen() && !config.getPaused())) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = config.getSupplyCap();
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint256 tokenDecimals = config.getDecimals();
        uint256 supplyCap = supplyCapInWholeTokens * 10 ** tokenDecimals;
        DataTypes.ReserveDataLegacy memory reserve = pool.getReserveData(asset());
        uint256 usedSupply =
            (aToken.scaledTotalSupply() + uint256(reserve.accruedToTreasury)).rayMul(reserve.liquidityIndex);

        if (usedSupply >= supplyCap) return 0;
        return Math.min(supplyCap - usedSupply, super.maxDeposit(receiver));
    }

    /// @notice Returns the maximum number of shares that can be minted
    /// @dev Converts the max deposit amount to shares
    function maxMint(address receiver) public view override(BaseVault) returns (uint256) {
        return Math.min(convertToShares(maxDeposit(receiver)), super.maxMint(receiver));
    }

    /// @notice Returns the maximum amount that can be withdrawn by an owner
    /// @dev Limited by both owner's balance and Aave pool liquidity
    function maxWithdraw(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        // check if asset is paused
        DataTypes.ReserveConfigurationMap memory config = pool.getReserveData(asset()).configuration;
        if (!(config.getActive() && !config.getPaused())) {
            return 0;
        }

        uint256 cash = IERC20(asset()).balanceOf(address(aToken));
        uint256 assetsBalance = convertToAssets(balanceOf(owner));
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Returns the maximum number of shares that can be redeemed
    /// @dev Updates Superform implementation to allow the SizeMetaVault to redeem all
    /// @dev Limited by both owner's balance and Aave pool liquidity
    function maxRedeem(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        // check if asset is paused
        DataTypes.ReserveConfigurationMap memory config = pool.getReserveData(asset()).configuration;
        if (!(config.getActive() && !config.getPaused())) {
            return 0;
        }

        uint256 cash = IERC20(asset()).balanceOf(address(aToken));
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf(owner);
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// @notice Returns the total assets managed by this strategy
    /// @dev Returns the aToken balance since aTokens represent the underlying asset with accrued interest
    /// @dev Round down to avoid stealing assets in roundtrip operations https://github.com/a16z/erc4626-tests/issues/13
    function totalAssets() public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        /// @notice aTokens use rebasing to accrue interest, so the total assets is just the aToken balance
        uint256 liquidityIndex = pool.getReserveNormalizedIncome(address(asset()));
        return Math.mulDiv(aToken.scaledBalanceOf(address(this)), liquidityIndex, WadRayMath.RAY);
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
        // slither-disable-next-line unused-return
        pool.withdraw(asset(), assets, address(this));
        super._withdraw(caller, receiver, owner, assets, shares);
    }
}
