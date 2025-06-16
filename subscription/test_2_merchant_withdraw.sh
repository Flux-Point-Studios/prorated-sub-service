#!/bin/bash

echo "=== Test 2: Merchant/Partner Withdraw ==="
echo "This allows the merchant to claim their portion of locked tokens"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# 1. Get current script UTxO data
echo "1. Reading current script UTxO data..."
SCRIPT_TX_IN=$SCRIPT_TX
jq -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > current_datum.json

# 2. Check if there are claimable installments
echo "2. Checking for claimable installments..."
INSTALLMENTS=$(jq '.fields[6].list | length' current_datum.json)
echo "  - Number of installments: $INSTALLMENTS"

if [ "$INSTALLMENTS" -eq "0" ]; then
    echo "ERROR: No installments found. Run test_1_extend.sh first!"
    exit 1
fi

# 3. Check first installment
NOW_MS=$(($(date +%s%3N)))
FIRST_CLAIMABLE_AT=$(jq '.fields[6].list[0].fields[0].int' current_datum.json)
FIRST_CLAIMABLE_AMOUNT=$(jq '.fields[6].list[0].fields[1].int' current_datum.json)

echo "  - First installment claimable at: $FIRST_CLAIMABLE_AT"
echo "  - First installment amount: $FIRST_CLAIMABLE_AMOUNT AGENT"
echo "  - Current time: $NOW_MS"

if [ "$NOW_MS" -lt "$FIRST_CLAIMABLE_AT" ]; then
    WAIT_TIME=$(( ($FIRST_CLAIMABLE_AT - $NOW_MS) / 1000 ))
    echo "WARNING: Installment not claimable yet. Wait $WAIT_TIME seconds."
    echo "For testing, we'll proceed anyway..."
fi

# 4. Calculate merchant's share
SERVICE_FEE=$(jq '.fields[0].int' current_datum.json)
PARTNER_PERCENTAGE=$(jq '.fields[10].int' current_datum.json)

# Calculate merchant amount (considering partner percentage)
if [ "$PARTNER_PERCENTAGE" -gt "0" ]; then
    MERCHANT_AMOUNT=$(( $FIRST_CLAIMABLE_AMOUNT * (100 - $PARTNER_PERCENTAGE) / 100 ))
    PARTNER_AMOUNT=$(( $FIRST_CLAIMABLE_AMOUNT * $PARTNER_PERCENTAGE / 100 ))
    echo "  - Merchant gets: $MERCHANT_AMOUNT AGENT ($(( 100 - $PARTNER_PERCENTAGE ))%)"
    echo "  - Partner gets: $PARTNER_AMOUNT AGENT ($PARTNER_PERCENTAGE%)"
else
    MERCHANT_AMOUNT=$FIRST_CLAIMABLE_AMOUNT
    echo "  - Merchant gets: $MERCHANT_AMOUNT AGENT (100%)"
fi

# 5. Create new datum (remove first installment)
echo "5. Creating new datum..."
jq '.fields[6].list = .fields[6].list[1:]' current_datum.json > new_datum.json

# 6. Calculate datum hash
echo "6. Calculating new datum hash..."
cardano-cli conway transaction hash-script-data \
    --script-data-file new_datum.json > new_datum.hash
NEW_DHASH=$(cat new_datum.hash)

# 7. Create redeemer for MerchantWithdraw
echo "7. Creating MerchantWithdraw redeemer..."
cat > merchant_withdraw.redeemer.json <<EOF
{ "constructor": 1, "fields": [] }
EOF

# 8. Get current script value
CURRENT_LOVELACE=$(jq -r --arg k "$SCRIPT_TX_IN" '.[$k].value.lovelace' script_utxos.json)
CURRENT_AGENT=$(jq -r --arg k "$SCRIPT_TX_IN" --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.[$k].value[$p][$n]' script_utxos.json)
REMAINING_AGENT=$(( $CURRENT_AGENT - $MERCHANT_AMOUNT ))

echo "8. Script value update:"
echo "  - Current AGENT: $CURRENT_AGENT"
echo "  - Withdrawing: $MERCHANT_AMOUNT"
echo "  - Remaining: $REMAINING_AGENT"

# 9. Build value for script output
NEW_VALUE="$CURRENT_LOVELACE + 1 ${POLICY_ID}.${ASSET_HEX} + $REMAINING_AGENT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"

# 10. Query merchant UTxOs for collateral
echo "9. Finding merchant collateral..."
query_utxos "$MERCHANT_ADDR" > merchant_utxos.json
COLLATERAL_TX=$(jq -r '.[] | select(.amount | length == 1 and .amount[0].unit == "lovelace" and (.amount[0].quantity | tonumber) >= 5000000) | 
    .tx_hash + "#" + (.output_index | tostring)
' merchant_utxos.json | head -1)

if [ -z "$COLLATERAL_TX" ]; then
    echo "WARNING: No collateral found for merchant. Using admin collateral..."
    COLLATERAL_TX="ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0"
fi

# 11. Get protocol parameters
get_protocol_params

# 12. Build the MerchantWithdraw transaction
echo "10. Building MerchantWithdraw transaction..."
cardano-cli conway transaction build \
    --tx-in "$SCRIPT_TX_IN" \
    --tx-in-script-file "$SPEND_SCRIPT" \
    --tx-in-datum-file current_datum.json \
    --tx-in-redeemer-file merchant_withdraw.redeemer.json \
    --tx-in-collateral "$COLLATERAL_TX" \
    --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \
    --tx-out-datum-hash "$NEW_DHASH" \
    --tx-out "$MERCHANT_ADDR+2000000 + $MERCHANT_AMOUNT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
    --change-address "$MERCHANT_ADDR" \
    --required-signer wallets/merchant/payment.skey \
    --invalid-before $((NOW_MS / 1000 - 300)) \
    --invalid-hereafter $((FIRST_CLAIMABLE_AT / 1000 + 3600)) \
    --out-file merchant_withdraw.txbody \
    --mainnet

if [ $? -eq 0 ]; then
    echo "11. Transaction built successfully!"
    
    # Sign transaction
    echo "12. Signing transaction..."
    cardano-cli conway transaction sign \
        --tx-body-file merchant_withdraw.txbody \
        --signing-key-file wallets/merchant/payment.skey \
        --out-file merchant_withdraw.tx.signed \
        --mainnet
    
    echo "13. Transaction ready to submit!"
    echo "    Run: submit_tx merchant_withdraw.tx.signed"
    
    # Show transaction details
    cardano-cli conway transaction view --tx-file merchant_withdraw.tx.signed
else
    echo "ERROR: Failed to build transaction"
    echo "Common issues:"
    echo "  - Installment not yet claimable (check timestamp)"
    echo "  - Invalid datum format"
    echo "  - Missing merchant signing key"
fi 