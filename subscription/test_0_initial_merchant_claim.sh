#!/bin/bash

echo "=== Test 0: Initial Merchant Claim ==="
echo "This allows the merchant to claim their service fee from the initial deposit"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# Set up jq alias
alias jq='python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py'

# 1. Query current script UTxOs first
echo "1. Querying current script UTxOs..."
cardano-cli conway query utxo \
    --address "$SCRIPT_ADDR" \
    --mainnet \
    --out-file script_utxos.json

if [ ! -f script_utxos.json ]; then
    echo "ERROR: Failed to query script UTxOs"
    exit 1
fi

# Get the first (and only) UTxO
echo "2. Reading current script UTxO data..."
SCRIPT_TX_IN=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r 'keys[0]' script_utxos.json)
echo "   Script UTxO: $SCRIPT_TX_IN"

# Extract the inline datum
python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > current_datum.json

# 2. Parse datum to get service fee
echo "3. Checking service fee..."
SERVICE_FEE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py '.fields[0].int' current_datum.json)
PARTNER_PERCENTAGE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py '.fields[10].int' current_datum.json)
CURRENT_AGENT=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r --arg k "$SCRIPT_TX_IN" --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.[$k].value[$p][$n]' script_utxos.json)

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

# 3. Calculate remaining value
REMAINING_AGENT=$(( $CURRENT_AGENT - $SERVICE_FEE ))
echo "  - Remaining after claim: $REMAINING_AGENT AGENT"

# 4. Keep datum unchanged (no installments to remove)
echo "4. Preparing transaction..."
cp current_datum.json new_datum.json

# 5. Calculate datum hash
cardano-cli conway transaction hash-script-data \
    --script-data-file new_datum.json > new_datum.hash
NEW_DHASH=$(cat new_datum.hash)

# 6. Create redeemer for initial merchant claim
# Using MerchantWithdraw redeemer
cat > initial_claim.redeemer.json <<EOF
{ "constructor": 1, "fields": [] }
EOF

# 7. Get current lovelace
CURRENT_LOVELACE=$(python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py -r --arg k "$SCRIPT_TX_IN" '.[$k].value.lovelace' script_utxos.json)

# 8. Build value for script output (minus service fee)
NEW_VALUE="$CURRENT_LOVELACE + 1 ${POLICY_ID}.${ASSET_HEX} + $REMAINING_AGENT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"

# 9. Get protocol parameters (this might take a moment)
echo "5. Getting protocol parameters..."
get_protocol_params

# 10. Build the transaction
echo "6. Building initial claim transaction..."
cardano-cli conway transaction build \
    --tx-in "$SCRIPT_TX_IN" \
    --tx-in-script-file "$SPEND_SCRIPT" \
    --tx-in-datum-file current_datum.json \
    --tx-in-redeemer-file initial_claim.redeemer.json \
    --tx-in-collateral "$COLLATERAL_TX" \
    --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \
    --tx-out-datum-hash "$NEW_DHASH" \
    --tx-out "$MERCHANT_ADDR+2000000 + $MERCHANT_AMOUNT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
    --change-address "$MERCHANT_ADDR" \
    --required-signer wallets/merchant/payment.skey \
    --out-file initial_claim.txbody \
    --mainnet

if [ $? -eq 0 ]; then
    echo "7. Transaction built successfully!"
    
    # Sign transaction
    echo "8. Signing transaction..."
    cardano-cli conway transaction sign \
        --tx-body-file initial_claim.txbody \
        --signing-key-file wallets/merchant/payment.skey \
        --out-file initial_claim.tx.signed \
        --mainnet
    
    echo "9. Transaction ready to submit!"
    echo "   This will:"
    echo "   - Transfer $MERCHANT_AMOUNT AGENT to merchant as service fee"
    echo "   - Leave $REMAINING_AGENT AGENT in the contract"
    echo "   - Keep the NFT locked in the contract"
    echo ""
    echo "   To submit: cardano-cli conway transaction submit --tx-file initial_claim.tx.signed --mainnet"
    
    # Show transaction details
    echo ""
    echo "Transaction details:"
    cardano-cli conway transaction view --tx-file initial_claim.tx.signed
else
    echo "ERROR: Failed to build transaction"
    echo "Note: The validator might require specific conditions for initial claim"
fi 