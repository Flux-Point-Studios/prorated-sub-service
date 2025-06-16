#!/bin/bash

echo "=== Initial Merchant Claim Preparation ==="
echo "This prepares the data needed to claim the service fee"
echo

# Load environment
source setup_env.sh

# Use Python for JSON processing
alias jq='python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py'

# 1. Use your existing quick_check.py to see current state
echo "1. Current contract state:"
python3 quick_check.py
echo

# 2. Create the redeemer file
echo "2. Creating redeemer for MerchantWithdraw..."
cat > merchant_claim.redeemer.json <<EOF
{ "constructor": 1, "fields": [] }
EOF
echo "   Created: merchant_claim.redeemer.json"

# 3. Show the transaction details
echo ""
echo "3. Transaction details for initial claim:"
echo "   - Input: $SCRIPT_TX (from script)"
echo "   - Collateral: Your collateral UTxO"
echo "   - Redeemer: MerchantWithdraw (constructor 1)"
echo "   - Signer: Merchant wallet"
echo ""
echo "   Outputs:"
echo "   - To Script: 4 ADA + 1 NFT + 9,000 AGENT (keeping datum unchanged)"
echo "   - To Merchant: 2 ADA + 1,000 AGENT (service fee)"
echo ""
echo "4. Next steps:"
echo "   Option A: Use Demeter (recommended since you used it before):"
echo "   - Go to your Demeter workspace"
echo "   - Use the transaction building commands from VALIDATOR_TESTING_STATUS.md"
echo "   - But with MerchantWithdraw redeemer instead of Extend"
echo ""
echo "   Option B: Use another Cardano transaction builder that supports Blockfrost"
echo ""
echo "The key is that this uses the MerchantWithdraw action to claim the initial"
echo "service fee (1,000 AGENT) without touching installments." 