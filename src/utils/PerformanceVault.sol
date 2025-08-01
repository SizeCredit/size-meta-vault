// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseVault} from "@src/utils/BaseVault.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PerformanceVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Vault that collects performance fees
/// @dev performanceFee = (currentPPS - highWaterMark) * totalSupply * feePercent
///      - currentPPS = current price per share = totalAssets() / totalSupply()
///      - highWaterMark = highest PPS previously recorded (stored in state)
///      - feePercent = fee percentage (e.g., 20% = 0.2e18)
///      - totalSupply = total shares in circulation
///      - Fees are only charged when the vault makes a profit, i.e., current PPS > highWaterMark.
/// Reference https://docs.dhedge.org/dhedge-protocol/vault-fees/performance-fees
abstract contract PerformanceVault is BaseVault {
    uint256 public constant PERCENT = 1e18;
    uint256 public constant MAXIMUM_PERFORMANCE_FEE_PERCENT = 0.5e18;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public highWaterMark;
    uint256 public performanceFeePercent;
    address public feeRecipient;
    uint256[47] private __gap;

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error PerformanceFeePercentTooHigh(uint256 performanceFeePercent, uint256 maximumPerformanceFeePercent);

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event PerformanceFeePercentSet(
        uint256 indexed performanceFeePercentBefore, uint256 indexed performanceFeePercentAfter
    );
    event FeeRecipientSet(address indexed feeRecipientBefore, address indexed feeRecipientAfter);
    event HighWaterMarkUpdated(uint256 highWaterMarkBefore, uint256 highWaterMarkAfter);
    event PerformanceFeeMinted(address indexed to, uint256 shares, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the PerformanceVault with a fee recipient and performance fee percent
    // solhint-disable-next-line func-name-mixedcase
    function __PerformanceVault_init(address feeRecipient_, uint256 performanceFeePercent_) internal onlyInitializing {
        _setFeeRecipient(feeRecipient_);
        _setPerformanceFeePercent(performanceFeePercent_);
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier to ensure the performance fee is minted before the function is executed
    modifier mintPerformanceFee() {
        _mintPerformanceFee();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the performance fee percent
    /// @dev Reverts if the performance fee percent is greater than the maximum performance fee percent
    function _setPerformanceFeePercent(uint256 performanceFeePercent_) internal {
        if (performanceFeePercent_ > MAXIMUM_PERFORMANCE_FEE_PERCENT) {
            revert PerformanceFeePercentTooHigh(performanceFeePercent_, MAXIMUM_PERFORMANCE_FEE_PERCENT);
        }

        uint256 performanceFeePercentBefore = performanceFeePercent;
        // slither-disable-next-line incorrect-equality
        if (performanceFeePercentBefore == 0 && performanceFeePercent_ > 0 && highWaterMark == 0) {
            _setHighWaterMark(_pps());
        }

        performanceFeePercent = performanceFeePercent_;
        emit PerformanceFeePercentSet(performanceFeePercentBefore, performanceFeePercent_);
    }

    /// @notice Sets the fee recipient
    function _setFeeRecipient(address feeRecipient_) internal {
        if (feeRecipient_ == address(0)) {
            revert NullAddress();
        }
        address feeRecipientBefore = feeRecipient;
        feeRecipient = feeRecipient_;
        emit FeeRecipientSet(feeRecipientBefore, feeRecipient_);
    }

    /// @notice Returns the price per share
    function _pps() internal view returns (uint256) {
        uint256 totalAssets_ = totalAssets();
        uint256 totalSupply_ = totalSupply();
        return totalSupply_ > 0 ? Math.mulDiv(totalAssets_, PERCENT, totalSupply_) : PERCENT;
    }

    /// @notice Mints performance fees if applicable
    /// @dev Using `convertToShares(feeShares)` would not be correct because once those shares are minted, the PPS changes,
    ///        and the asset value of the minted shares is different to feeAssets.
    ///        We solve the equation: feeAssets = feeShares * (totalAssets + 1) / (totalSupply + 1 + feeShares)
    ///        Basically feeAssets = convertToAssets(feeShares), but adding feeShares to the totalSupply part during the calculation
    function _mintPerformanceFee() private {
        if (performanceFeePercent == 0) {
            return;
        }

        uint256 currentPPS = _pps();
        uint256 highWaterMarkBefore = highWaterMark;
        if (currentPPS > highWaterMarkBefore) {
            uint256 profitPerSharePercent = currentPPS - highWaterMarkBefore;
            uint256 totalProfitAssets = Math.mulDiv(profitPerSharePercent, totalSupply(), PERCENT);
            uint256 feeAssets = Math.mulDiv(totalProfitAssets, performanceFeePercent, PERCENT);
            uint256 feeShares =
                Math.mulDiv(feeAssets, totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1 - feeAssets);

            if (feeShares > 0) {
                _setHighWaterMark(currentPPS);
                _mint(feeRecipient, feeShares);
                emit PerformanceFeeMinted(feeRecipient, feeShares, feeAssets);
            }
        }
    }

    /// @notice Sets the high water mark
    function _setHighWaterMark(uint256 highWaterMark_) internal {
        uint256 highWaterMarkBefore = highWaterMark;
        highWaterMark = highWaterMark_;
        emit HighWaterMarkUpdated(highWaterMarkBefore, highWaterMark_);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        mintPerformanceFee
        emitVaultStatus
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        mintPerformanceFee
        emitVaultStatus
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        mintPerformanceFee
        emitVaultStatus
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        mintPerformanceFee
        emitVaultStatus
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }
}
