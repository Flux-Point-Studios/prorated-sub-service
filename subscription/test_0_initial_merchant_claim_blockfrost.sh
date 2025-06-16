#!/bin/bash

echo "=== Test 0: Initial Merchant Claim (Blockfrost) ==="
echo "This allows the merchant to claim their service fee from the initial deposit"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# Set up jq alias
alias jq='python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py'

# 1. Query current script UTxOs using Blockfrost
echo "1. Querying current script UTxOs via Blockfrost..."
curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
    "$BLOCKFROST_API_URL/addresses/$SCRIPT_ADDR/utxos" > blockfrost_utxos.json

# Check if we got UTxOs
if [ ! -s blockfrost_utxos.json ] || grep -q "error" blockfrost_utxos.json; then
    echo "ERROR: Failed to query UTxOs from Blockfrost"
    cat blockfrost_utxos.json
    exit 1
fi

# Get the first UTxO
echo "2. Processing UTxO data..."
SCRIPT_TX_HASH=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r '.[0].tx_hash' blockfrost_utxos.json)
SCRIPT_TX_INDEX=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r '.[0].output_index' blockfrost_utxos.json)
SCRIPT_TX_IN="${SCRIPT_TX_HASH}#${SCRIPT_TX_INDEX}"
echo "   Script UTxO: $SCRIPT_TX_IN"

# Get the inline datum value
INLINE_DATUM=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r '.[0].inline_datum' blockfrost_utxos.json)
echo "$INLINE_DATUM" > current_datum.json

# Parse datum to get service fee
echo "3. Checking service fee..."
SERVICE_FEE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py '.fields[0].int' current_datum.json)
PARTNER_PERCENTAGE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py '.fields[10].int' current_datum.json)

# Get current AGENT amount from UTxO
AGENT_AMOUNT_STR=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r '.[] | select(.unit == "'${AGENT_POLICY_ID}${AGENT_ASSET_NAME}'") | .quantity' blockfrost_utxos.json)
CURRENT_AGENT=${AGENT_AMOUNT_STR:-0}

echo "  - Service fee: $SERVICE_FEE AGENT"
echo "  - Current AGENT in contract: $CURRENT_AGENT"
echo "  - Partner percentage: $PARTNER_PERCENTAGE%"

# Calculate merchant's share of service fee
if [ "$PARTNER_PERCENTAGE" -gt "0" ]; then
    MERCHANT_AMOUNT=$(( $SERVICE_FEE * (100 - $PARTNER_PERCENTAGE) / 100 ))
    PARTNER_AMOUNT=$(( $SERVICE_FEE * $PARTNER_PERCENTAGE / 100 ))
    echo "  - Merchant gets: $MERCHANT_AMOUNT AGENT ($(( 100 - $PARTNER_PERCENTAGE ))%)"
    echo "  - Partner gets: $PARTNER_AMOUNT AGENT ($PARTNER_PERCENTAGE%)"
else
    MERCHANT_AMOUNT=$SERVICE_FEE
    echo "  - Merchant gets: $MERCHANT_AMOUNT AGENT (100%)"
fi

# Calculate remaining value
REMAINING_AGENT=$(( $CURRENT_AGENT - $SERVICE_FEE ))
echo "  - Remaining after claim: $REMAINING_AGENT AGENT"

# Keep datum unchanged (no installments to remove)
echo "4. Preparing transaction..."
cp current_datum.json new_datum.json

# Calculate datum hash
cardano-cli conway transaction hash-script-data \
    --script-data-file new_datum.json > new_datum.hash
NEW_DHASH=$(cat new_datum.hash)

# Create redeemer for initial merchant claim
cat > initial_claim.redeemer.json <<EOF
{ "constructor": 1, "fields": [] }
EOF

# Get current lovelace from UTxO
CURRENT_LOVELACE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r '.[] | select(.unit == "lovelace") | .quantity' blockfrost_utxos.json)

# Build value for script output (minus service fee)
NEW_VALUE="$CURRENT_LOVELACE + 1 ${POLICY_ID}.${ASSET_HEX} + $REMAINING_AGENT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"

# Get protocol parameters from Blockfrost
echo "5. Getting protocol parameters from Blockfrost..."
get_protocol_params

# For transaction building, we need a different approach since we can't use cardano-cli without a node
echo "6. Transaction building..."
echo ""
echo "Since you're using Blockfrost (no local node), you have two options:"
echo ""
echo "Option 1: Use a transaction building service or tool that works with Blockfrost"
echo "Option 2: Build the transaction manually using cardano-serialization-lib"
echo ""
echo "Transaction details:"
echo "  Input: $SCRIPT_TX_IN"
echo "  Script: $SPEND_SCRIPT"
echo "  Redeemer: MerchantWithdraw"
echo "  Outputs:"
echo "    - To Script: $CURRENT_LOVELACE lovelace + 1 NFT + $REMAINING_AGENT AGENT"
echo "    - To Merchant: 2000000 lovelace + $MERCHANT_AMOUNT AGENT"
echo ""
echo "The validator should accept this as it's claiming the initial service fee." 