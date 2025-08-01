// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

abstract contract PropertiesSpecifications {
    string constant RT_01 = "RT_01: Any two operations should not change convertToAssets(balanceOf) other users";
    string constant SOLVENCY_01 = "SOLVENCY_01: SUM(convertToAssets(balanceOf)) <= totalAssets()";
    string constant SOLVENCY_02 =
        "SOLVENCY_02: Direct deposit to strategy should not change convertToAssets(balanceOf) of the meta vault";
    string constant REBALANCE_01 = "REBALANCE_01: rebalance does not change balanceOf, convertToAssets(balanceOf)";
    string constant STRATEGY_01 = "STRATEGY_01: Removing a strategy does not change balanceOf";
    string constant STRATEGY_02 = "STRATEGY_02: The SizeMetaVault always has at least 1 strategy";
    string constant TOTAL_ASSETS_CAP_01 =
        "TOTAL_ASSETS_CAP_01: Deposit reverts if amount + totalAssets() >= totalAssetsCap()";
    string constant DEPOSIT_01 = "DEPOSIT_01: deposit(maxDeposit) should not revert";
    string constant MINT_01 = "MINT_01: mint(maxMint) should not revert";
    string constant WITHDRAW_01 = "WITHDRAW_01: withdraw(maxWithdraw) should not revert";
    string constant WITHDRAW_02 = "WITHDRAW_02: withdraw(maxWithdraw) should leave balanceOf == 0";
    string constant REDEEM_01 = "REDEEM_01: redeem(maxRedeem) should not revert";
    string constant REDEEM_02 = "REDEEM_02: redeem(maxRedeem) should leave balanceOf == 0";
}
