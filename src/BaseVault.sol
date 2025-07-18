// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MulticallUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Auth} from "@src/Auth.sol";
import {DEFAULT_ADMIN_ROLE, PAUSER_ROLE, STRATEGIST_ROLE} from "@src/Auth.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IBaseVault} from "@src/IBaseVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title BaseVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Abstract base contract for all vaults in the Size Meta Vault system
/// @dev Provides common functionality including ERC4626 compliance, access control, and upgradeability
abstract contract BaseVault is
    IBaseVault,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    MulticallUpgradeable,
    UUPSUpgradeable
{
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    Auth public auth;
    uint256 public deadAssets;
    uint256 public totalAssetsCap;
    uint256[47] private __gap;

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error NullAddress();
    error NullAmount();
    error InvalidAsset(address asset);

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuthSet(address indexed auth);
    event DeadAssetsSet(uint256 indexed deadAssets);
    event TotalAssetsCapSet(uint256 indexed totalAssetsCapBefore, uint256 indexed totalAssetsCapAfter);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR / INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the BaseVault with necessary parameters
    /// @dev Sets up all inherited contracts and makes the first deposit to prevent inflation attacks
    function initialize(
        Auth auth_,
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 firstDepositAmount_
    ) public virtual initializer {
        __ERC4626_init(asset_);
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ReentrancyGuard_init();
        __Pausable_init();
        __Multicall_init();
        __UUPSUpgradeable_init();

        if (address(auth_) == address(0)) {
            revert NullAddress();
        }
        if (firstDepositAmount_ == 0) {
            revert NullAmount();
        }

        auth = auth_;
        emit AuthSet(address(auth_));

        deadAssets = firstDepositAmount_;
        emit DeadAssetsSet(firstDepositAmount_);

        _setTotalAssetsCap(type(uint256).max);

        deposit(firstDepositAmount_, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier to restrict function access to addresses with specific roles
    /// @dev Reverts if the caller doesn't have the required role
    modifier onlyAuth(bytes32 role) {
        if (!auth.hasRole(role, msg.sender)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    /// @notice Modifier to ensure the contract is not paused
    /// @dev Checks both local pause state and global pause state from Auth
    modifier notPaused() {
        if (paused() || auth.paused()) revert EnforcedPause();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @dev Only addresses with DEFAULT_ADMIN_ROLE can authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyAuth(DEFAULT_ADMIN_ROLE) {}

    /// @notice Pauses the vault
    /// @dev Only addresses with PAUSER_ROLE can pause the vault
    function pause() external onlyAuth(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Only addresses with PAUSER_ROLE can unpause the vault
    function unpause() external onlyAuth(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Sets the maximum total assets of the vault
    /// @dev Only callable by the auth contract
    /// @dev Lowering the total assets cap does not affect existing deposited assets
    function setTotalAssetsCap(uint256 totalAssetsCap_) external onlyAuth(STRATEGIST_ROLE) {
        _setTotalAssetsCap(totalAssetsCap_);
    }

    /// @notice Sets the maximum total assets of the vault
    function _setTotalAssetsCap(uint256 totalAssetsCap_) private {
        uint256 oldTotalAssetsCap = totalAssetsCap;
        totalAssetsCap = totalAssetsCap_;
        emit TotalAssetsCapSet(oldTotalAssetsCap, totalAssetsCap_);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the number of decimals for the vault token
    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, ERC4626Upgradeable, IERC20Metadata)
        returns (uint8)
    {
        return super.decimals();
    }

    /// @notice Internal function called during token transfers
    /// @dev Ensures transfers only happen when the contract is not paused and that no reentrancy is possible
    function _update(address from, address to, uint256 value) internal override nonReentrant notPaused {
        super._update(from, to, value);
    }

    /// @notice Returns the maximum amount that can be deposited
    /// @dev Returns type(uint256).max if no total assets cap is set
    function maxDeposit(address) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return totalAssetsCap == type(uint256).max ? type(uint256).max : totalAssetsCap - totalAssets();
    }

    /// @notice Returns the maximum amount that can be minted
    /// @dev Returns type(uint256).max if no total assets cap is set
    function maxMint(address receiver) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return totalAssetsCap == type(uint256).max ? type(uint256).max : convertToShares(maxDeposit(receiver));
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override(ERC4626Upgradeable)
        returns (uint256)
    {
        return assets.mulDiv(
            totalSupply() + 10 ** _decimalsOffset(), totalAssets() + (rounding == Math.Rounding.Floor ? 1 : 0), rounding
        );
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override(ERC4626Upgradeable)
        returns (uint256)
    {
        return shares.mulDiv(
            totalAssets() + (rounding == Math.Rounding.Ceil ? 1 : 0), totalSupply() + 10 ** _decimalsOffset(), rounding
        );
    }
}
