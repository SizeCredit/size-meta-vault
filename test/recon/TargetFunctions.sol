// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Targets
// NOTE: Always import and apply them in alphabetical order, so much easier to debug!
import {AaveStrategyVaultTargets} from "./targets/project/AaveStrategyVaultTargets.sol";
import {AdminTargets} from "./targets/AdminTargets.sol";
import {CashStrategyVaultTargets} from "./targets/project/CashStrategyVaultTargets.sol";
import {DoomsdayTargets} from "./targets/DoomsdayTargets.sol";
import {ERC4626MustNotRevertTargets} from "./targets/project/ERC4626MustNotRevertTargets.sol";
import {ERC4626StrategyVaultTargets} from "./targets/project/ERC4626StrategyVaultTargets.sol";
import {ManagersTargets} from "./targets/ManagersTargets.sol";
import {SizeMetaVaultTargets} from "./targets/project/SizeMetaVaultTargets.sol";
import {AuthTargets} from "./targets/project/AuthTargets.sol";

abstract contract TargetFunctions is
    AaveStrategyVaultTargets,
    AdminTargets,
    CashStrategyVaultTargets,
    DoomsdayTargets,
    AuthTargets,
    ERC4626MustNotRevertTargets,
    ERC4626StrategyVaultTargets,
    ManagersTargets,
    SizeMetaVaultTargets
{
/// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

/// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
