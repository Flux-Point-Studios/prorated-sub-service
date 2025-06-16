#!/bin/bash

echo "=== Updating UTxO Data from Blockfrost ==="
echo

# Load environment
source setup_env.sh
source .env

# Function to get detailed UTxO info
get_utxo_details() {
    local tx_hash=$1
    local output_index=$2
    
    curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
        "$BLOCKFROST_API_URL/txs/$tx_hash/utxos" | \
    jq --arg idx "$output_index" '.outputs[$idx | tonumber]'
}

# Update script UTxOs
echo "1. Updating script UTxO data..."
TX_HASH=$(echo $SCRIPT_TX | cut -d'#' -f1)
TX_IDX=$(echo $SCRIPT_TX | cut -d'#' -f2)

UTXO_DATA=$(get_utxo_details $TX_HASH $TX_IDX)

if [ "$UTXO_DATA" != "null" ] && [ -n "$UTXO_DATA" ]; then
    # Create script_utxos.json in the expected format
    echo "{
    \"$SCRIPT_TX\": {
        \"address\": \"$SCRIPT_ADDR\",
        \"datum\": null,
        \"inlineDatum\": $(echo "$UTXO_DATA" | jq '.inline_datum'),
        \"inlineDatumRaw\": \"$(echo "$UTXO_DATA" | jq -r '.data_hash // empty')\",
        \"inlineDatumhash\": \"$(echo "$UTXO_DATA" | jq -r '.data_hash // empty')\",
        \"referenceScript\": null,
        \"value\": {
            \"lovelace\": $(echo "$UTXO_DATA" | jq '.amount[] | select(.unit == "lovelace") | .quantity | tonumber'),
            \"$AGENT_POLICY_ID\": {
                \"$AGENT_ASSET_NAME\": $(echo "$UTXO_DATA" | jq --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.amount[] | select(.unit == ($p + $n)) | .quantity | tonumber // 0')
            },
            \"$POLICY_ID\": {
                \"$ASSET_HEX\": $(echo "$UTXO_DATA" | jq --arg p "$POLICY_ID" --arg n "$ASSET_HEX" '.amount[] | select(.unit == ($p + $n)) | .quantity | tonumber // 0')
            }
        }
    }
}" > script_utxos_new.json

    # Backup old file and replace
    if [ -f script_utxos.json ]; then
        cp script_utxos.json script_utxos.backup.json
    fi
    mv script_utxos_new.json script_utxos.json
    
    echo "✅ Script UTxO data updated successfully!"
else
    echo "❌ Failed to fetch script UTxO data"
    echo "   Check that the transaction hash is correct: $SCRIPT_TX"
    exit 1
fi

# Update wallet UTxOs
echo
echo "2. Updating wallet UTxOs..."

# Admin wallet
echo "   - Admin wallet..."
curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
    "$BLOCKFROST_API_URL/addresses/$PAYMENT_ADDR/utxos" > admin_utxos_blockfrost.json

# Subscriber wallet  
SUB_ADDR=$(cat wallets/subscriber/payment.addr)
echo "   - Subscriber wallet..."
curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
    "$BLOCKFROST_API_URL/addresses/$SUB_ADDR/utxos" > sub_utxos_blockfrost.json

# Merchant wallet
echo "   - Merchant wallet..."
curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
    "$BLOCKFROST_API_URL/addresses/$MERCHANT_ADDR/utxos" > merchant_utxos_blockfrost.json

echo
echo "✅ All UTxO data updated!"
echo
echo "You can now run the test scripts:"
echo "  - ./check_status.sh      - Check current state"
echo "  - ./test_1_extend.sh     - Add installment"
echo "  - ./test_2_merchant_withdraw.sh - Merchant claim"
echo "  - ./test_3_unsubscribe.sh - Early cancellation"
echo "  - ./test_4_subscriber_withdraw.sh - Expired withdrawal" 