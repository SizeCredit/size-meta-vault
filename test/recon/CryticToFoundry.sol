// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {IVault} from "@src/utils/IVault.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";

// forge test --match-contract CryticToFoundry -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-test test_crytic -vvv
    function test_CryticToFoundry_01() public {
        sizeMetaVault_addStrategy(cryticSizeMetaVault);
        try this.sizeMetaVault_removeStrategy(
            cashStrategyVault,
            cryticSizeMetaVault,
            0,
            12309285055488365505482212365492300592776939712510733309382679362574362184841
        ) {
            assertTrue(false, "should revert");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(BaseVault.NullAmount.selector));
        }
    }

    function test_CryticToFoundry_02() public {
        cashStrategyVault_setTotalAssetsCap(0);
        cashStrategyVault_deposit(0, 0xA0a075bA2bB014bf8F08bf91DEd27002bd87B9eE);
    }

    function test_CryticToFoundry_03() public {
        sizeMetaVault_removeStrategy(cashStrategyVault, aaveStrategyVault, 1, 0);
        erc4626_mustNotRevert_convertToShares(
            2864474371869477837766289424800920762713068510290572746720344906210731950275
        );
    }

    function test_CryticToFoundry_04() public {
        sizeMetaVault_removeStrategy(
            erc4626StrategyVault,
            cashStrategyVault,
            12365772636688392640122225467814873084244657338905471971496106064405562446679,
            61713837595357171402281262959146600068603794227103927492545261743669128
        );
        sizeMetaVault_removeStrategy(cashStrategyVault, aaveStrategyVault, 312, 0);
        aaveStrategyVault_setTotalAssetsCap(
            25150558811799922860235757451418943390228657999138837874545548576258909183598
        );
        erc4626_mustNotRevert_maxMint(0x51e35255066cb44807Ca732b5550A53fd73b0A1c);
    }
}
