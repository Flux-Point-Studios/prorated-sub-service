#!/usr/bin/env python3
"""
Initial Merchant Claim Test
Claims the service fee from the initial 10,000 AGENT deposit
"""

import os
import subprocess
import json
import sys

# Configuration
SCRIPT_TX = "85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0"
SCRIPT_ADDR = "addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf"
MERCHANT_ADDR = "addr1qywdfe..."  # Your merchant address
POLICY_ID = "efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb"
ASSET_HEX = "4147454e545f5355425f4e4654"
AGENT_POLICY_ID = "97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec"
AGENT_ASSET_NAME = "54616c6f73"
SPEND_SCRIPT = "artifacts-mainnet/spend_policy.plutus"
COLLATERAL_TX = "ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0"

def run_cardano_cli(args):
    """Run cardano-cli command"""
    cmd = ["cardano-cli", "conway"] + args
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return None
    return result.stdout

def main():
    print("=== Initial Merchant Claim Test ===")
    print("This claims the service fee from the initial 10,000 AGENT deposit\n")
    
    # 1. Query current UTxO
    print("1. Querying current script UTxO...")
    utxo_output = run_cardano_cli(["query", "utxo", "--address", SCRIPT_ADDR, "--mainnet"])
    if not utxo_output:
        print("Failed to query UTxO")
        return
    
    print(f"Current UTxO:\n{utxo_output}")
    
    # 2. Get the inline datum
    print("\n2. Fetching inline datum...")
    # Note: This would need to parse the UTxO output and extract the datum
    # For now, we'll use the known values
    
    SERVICE_FEE = 1000000  # 1,000 AGENT (with 6 decimals)
    CURRENT_AGENT = 10000000000  # 10,000 AGENT (with 6 decimals)
    PARTNER_PERCENTAGE = 0
    
    print(f"  - Service fee: {SERVICE_FEE // 1000000} AGENT")
    print(f"  - Current AGENT in contract: {CURRENT_AGENT // 1000000} AGENT")
    print(f"  - Partner percentage: {PARTNER_PERCENTAGE}%")
    
    # 3. Calculate amounts
    if PARTNER_PERCENTAGE > 0:
        MERCHANT_AMOUNT = SERVICE_FEE * (100 - PARTNER_PERCENTAGE) // 100
        PARTNER_AMOUNT = SERVICE_FEE * PARTNER_PERCENTAGE // 100
        print(f"  - Merchant gets: {MERCHANT_AMOUNT // 1000000} AGENT ({100 - PARTNER_PERCENTAGE}%)")
        print(f"  - Partner gets: {PARTNER_AMOUNT // 1000000} AGENT ({PARTNER_PERCENTAGE}%)")
    else:
        MERCHANT_AMOUNT = SERVICE_FEE
        print(f"  - Merchant gets: {MERCHANT_AMOUNT // 1000000} AGENT (100%)")
    
    REMAINING_AGENT = CURRENT_AGENT - SERVICE_FEE
    print(f"  - Remaining after claim: {REMAINING_AGENT // 1000000} AGENT")
    
    # 4. Create redeemer
    print("\n3. Creating redeemer...")
    redeemer = {"constructor": 1, "fields": []}  # MerchantWithdraw
    with open("initial_claim.redeemer.json", "w") as f:
        json.dump(redeemer, f)
    
    # 5. Build transaction
    print("\n4. Building transaction...")
    print("   Note: In a real scenario, you would:")
    print("   - Keep the datum unchanged")
    print("   - Transfer service fee to merchant")
    print("   - Keep remaining AGENT and NFT in contract")
    
    # Show the command that would be run
    print("\nTransaction command would be:")
    print(f"""
cardano-cli conway transaction build \\
    --tx-in {SCRIPT_TX} \\
    --tx-in-script-file {SPEND_SCRIPT} \\
    --tx-in-datum-file current_datum.json \\
    --tx-in-redeemer-file initial_claim.redeemer.json \\
    --tx-in-collateral {COLLATERAL_TX} \\
    --tx-out "{SCRIPT_ADDR}+4000000 + 1 {POLICY_ID}.{ASSET_HEX} + {REMAINING_AGENT} {AGENT_POLICY_ID}.{AGENT_ASSET_NAME}" \\
    --tx-out "{MERCHANT_ADDR}+2000000 + {MERCHANT_AMOUNT} {AGENT_POLICY_ID}.{AGENT_ASSET_NAME}" \\
    --change-address {MERCHANT_ADDR} \\
    --required-signer wallets/merchant/payment.skey \\
    --out-file initial_claim.txbody \\
    --mainnet
    """)
    
    print("\nTo actually run this transaction:")
    print("1. Open WSL terminal")
    print("2. cd /mnt/c/GitHubRepos/prorated-sub-service/subscription")
    print("3. Run: ./test_0_initial_merchant_claim.sh")

if __name__ == "__main__":
    main() 