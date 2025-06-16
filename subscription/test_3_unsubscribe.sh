#!/bin/bash

echo "=== Test 3: Unsubscribe (Early Cancellation) ==="
echo "This allows the subscriber to cancel and get a prorated refund"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# 1. Get current script UTxO data
echo "1. Reading current script UTxO data..."
SCRIPT_TX_IN=$SCRIPT_TX
jq -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > current_datum.json

# 2. Calculate refund amounts
echo "2. Calculating prorated refund..."
NOW=$(date +%s)
NOW_MS=$((NOW * 1000))

# Get datum values
SERVICE_FEE=$(jq '.fields[0].int' current_datum.json)
PENALTY_FEE=$(jq '.fields[1].int' current_datum.json)
INTERVAL_LENGTH=$(jq '.fields[2].int' current_datum.json)
SUB_START=$(jq '.fields[3].int' current_datum.json)
SUB_END=$(jq '.fields[4].int' current_datum.json)
ORIGINAL_END=$(jq '.fields[5].int' current_datum.json)

# Calculate time remaining
TIME_REMAINING=$((SUB_END - NOW))
if [ "$TIME_REMAINING" -lt "0" ]; then
    echo "ERROR: Subscription already expired. Use SubscriberWithdraw instead."
    exit 1
fi

# Get current AGENT balance
CURRENT_AGENT=$(jq -r --arg k "$SCRIPT_TX_IN" --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.[$k].value[$p][$n]' script_utxos.json)

# Calculate prorated amounts
TOTAL_DURATION=$((SUB_END - SUB_START))
TIME_USED=$((NOW - SUB_START))
PERCENTAGE_USED=$((TIME_USED * 100 / TOTAL_DURATION))
PERCENTAGE_REMAINING=$((100 - PERCENTAGE_USED))

# Calculate refund (minus penalty)
GROSS_REFUND=$((CURRENT_AGENT * PERCENTAGE_REMAINING / 100))
NET_REFUND=$((GROSS_REFUND - PENALTY_FEE))
MERCHANT_GETS=$((CURRENT_AGENT - NET_REFUND))

echo "  - Subscription start: $(date -d @$((SUB_START/1000)))"
echo "  - Subscription end: $(date -d @$((SUB_END/1000)))"
echo "  - Current time: $(date -d @$NOW)"
echo "  - Time used: $PERCENTAGE_USED%"
echo "  - Current AGENT: $CURRENT_AGENT"
echo "  - Penalty fee: $PENALTY_FEE"
echo "  - Gross refund: $GROSS_REFUND AGENT"
echo "  - Net refund to subscriber: $NET_REFUND AGENT"
echo "  - Merchant receives: $MERCHANT_GETS AGENT"

# 3. Create redeemer for Unsubscribe
echo "3. Creating Unsubscribe redeemer..."
cat > unsubscribe.redeemer.json <<EOF
{ "constructor": 2, "fields": [] }
EOF

# 4. Query for collateral
echo "4. Finding collateral..."
SUB_ADDR=$(cat wallets/subscriber/payment.addr)
query_utxos "$SUB_ADDR" > sub_utxos.json
COLLATERAL_TX=$(jq -r '.[] | select(.amount | length == 1 and .amount[0].unit == "lovelace" and (.amount[0].quantity | tonumber) >= 5000000) | 
    .tx_hash + "#" + (.output_index | tostring)
' sub_utxos.json | head -1)

if [ -z "$COLLATERAL_TX" ]; then
    echo "WARNING: No collateral found. Using default..."
    COLLATERAL_TX="ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0"
fi

# 5. Get protocol parameters
get_protocol_params

# 6. Build the Unsubscribe transaction
echo "5. Building Unsubscribe transaction..."
echo "   Note: This will burn the NFT and distribute tokens"

# The contract requires burning the NFT
BURN_VALUE="-1 ${POLICY_ID}.${ASSET_HEX}"

cardano-cli conway transaction build \
    --tx-in "$SCRIPT_TX_IN" \
    --tx-in-script-file "$SPEND_SCRIPT" \
    --tx-in-datum-file current_datum.json \
    --tx-in-redeemer-file unsubscribe.redeemer.json \
    --tx-in-collateral "$COLLATERAL_TX" \
    --tx-out "$SUB_ADDR+2000000 + $NET_REFUND ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
    --tx-out "$MERCHANT_ADDR+2000000 + $MERCHANT_GETS ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
    --mint "$BURN_VALUE" \
    --mint-script-file artifacts-mainnet/mint_policy.plutus \
    --mint-redeemer-file unsubscribe.redeemer.json \
    --change-address "$SUB_ADDR" \
    --required-signer wallets/subscriber/payment.skey \
    --out-file unsubscribe.txbody \
    --mainnet

if [ $? -eq 0 ]; then
    echo "6. Transaction built successfully!"
    
    # Sign transaction
    echo "7. Signing transaction..."
    cardano-cli conway transaction sign \
        --tx-body-file unsubscribe.txbody \
        --signing-key-file wallets/subscriber/payment.skey \
        --out-file unsubscribe.tx.signed \
        --mainnet
    
    echo "8. Transaction ready to submit!"
    echo "   This will:"
    echo "   - Burn the subscription NFT"
    echo "   - Return $NET_REFUND AGENT to subscriber"
    echo "   - Send $MERCHANT_GETS AGENT to merchant"
    echo ""
    echo "   Run: submit_tx unsubscribe.tx.signed"
    
    # Show transaction details
    cardano-cli conway transaction view --tx-file unsubscribe.tx.signed
else
    echo "ERROR: Failed to build transaction"
    echo "Common issues:"
    echo "  - Missing mint policy script"
    echo "  - Invalid redeemer format"
    echo "  - Insufficient balance for outputs"
fi 