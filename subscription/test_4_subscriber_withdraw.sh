#!/bin/bash

echo "=== Test 4: Subscriber Withdraw (After Expiry) ==="
echo "This allows the subscriber to reclaim tokens after subscription expires"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# 1. Get current script UTxO data
echo "1. Reading current script UTxO data..."
SCRIPT_TX_IN=$SCRIPT_TX
jq -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > current_datum.json

# 2. Check if subscription has expired
echo "2. Checking subscription status..."
NOW=$(date +%s)
NOW_MS=$((NOW * 1000))
SUB_END=$(jq '.fields[4].int' current_datum.json)

echo "  - Subscription end: $(date -d @$((SUB_END/1000)))"
echo "  - Current time: $(date -d @$NOW)"

if [ "$NOW" -lt "$((SUB_END/1000))" ]; then
    WAIT_TIME=$((SUB_END/1000 - NOW))
    echo "WARNING: Subscription not expired yet. Wait $WAIT_TIME seconds."
    echo "For testing purposes, we'll proceed anyway..."
fi

# 3. Get remaining tokens
echo "3. Checking remaining tokens..."
CURRENT_AGENT=$(jq -r --arg k "$SCRIPT_TX_IN" --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.[$k].value[$p][$n]' script_utxos.json)
CURRENT_LOVELACE=$(jq -r --arg k "$SCRIPT_TX_IN" '.[$k].value.lovelace' script_utxos.json)

echo "  - Remaining AGENT: $CURRENT_AGENT"
echo "  - Remaining ADA: $(echo "scale=6; $CURRENT_LOVELACE / 1000000" | bc) ADA"

# 4. Create redeemer for SubscriberWithdraw
echo "4. Creating SubscriberWithdraw redeemer..."
cat > subscriber_withdraw.redeemer.json <<EOF
{ "constructor": 3, "fields": [] }
EOF

# 5. Query for collateral
echo "5. Finding collateral..."
SUB_ADDR=$(cat wallets/subscriber/payment.addr)
query_utxos "$SUB_ADDR" > sub_utxos.json
COLLATERAL_TX=$(jq -r '.[] | select(.amount | length == 1 and .amount[0].unit == "lovelace" and (.amount[0].quantity | tonumber) >= 5000000) | 
    .tx_hash + "#" + (.output_index | tostring)
' sub_utxos.json | head -1)

if [ -z "$COLLATERAL_TX" ]; then
    echo "WARNING: No collateral found. Using default..."
    COLLATERAL_TX="ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0"
fi

# 6. Get protocol parameters
get_protocol_params

# 7. Build the SubscriberWithdraw transaction
echo "6. Building SubscriberWithdraw transaction..."
echo "   Note: This will burn the NFT and return all remaining tokens"

# The contract requires burning the NFT
BURN_VALUE="-1 ${POLICY_ID}.${ASSET_HEX}"

# Build transaction based on whether there are remaining AGENT tokens
if [ "$CURRENT_AGENT" -gt "0" ]; then
    echo "   Withdrawing $CURRENT_AGENT AGENT tokens..."
    cardano-cli conway transaction build \
        --tx-in "$SCRIPT_TX_IN" \
        --tx-in-script-file "$SPEND_SCRIPT" \
        --tx-in-datum-file current_datum.json \
        --tx-in-redeemer-file subscriber_withdraw.redeemer.json \
        --tx-in-collateral "$COLLATERAL_TX" \
        --tx-out "$SUB_ADDR+2000000 + $CURRENT_AGENT ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
        --mint "$BURN_VALUE" \
        --mint-script-file artifacts-mainnet/mint_policy.plutus \
        --mint-redeemer-file subscriber_withdraw.redeemer.json \
        --change-address "$SUB_ADDR" \
        --required-signer wallets/subscriber/payment.skey \
        --invalid-after $((SUB_END/1000 + 86400)) \
        --out-file subscriber_withdraw.txbody \
        --mainnet
else
    echo "   No AGENT tokens remaining, only withdrawing ADA..."
    cardano-cli conway transaction build \
        --tx-in "$SCRIPT_TX_IN" \
        --tx-in-script-file "$SPEND_SCRIPT" \
        --tx-in-datum-file current_datum.json \
        --tx-in-redeemer-file subscriber_withdraw.redeemer.json \
        --tx-in-collateral "$COLLATERAL_TX" \
        --mint "$BURN_VALUE" \
        --mint-script-file artifacts-mainnet/mint_policy.plutus \
        --mint-redeemer-file subscriber_withdraw.redeemer.json \
        --change-address "$SUB_ADDR" \
        --required-signer wallets/subscriber/payment.skey \
        --invalid-after $((SUB_END/1000 + 86400)) \
        --out-file subscriber_withdraw.txbody \
        --mainnet
fi

if [ $? -eq 0 ]; then
    echo "7. Transaction built successfully!"
    
    # Sign transaction
    echo "8. Signing transaction..."
    cardano-cli conway transaction sign \
        --tx-body-file subscriber_withdraw.txbody \
        --signing-key-file wallets/subscriber/payment.skey \
        --out-file subscriber_withdraw.tx.signed \
        --mainnet
    
    echo "9. Transaction ready to submit!"
    echo "   This will:"
    echo "   - Burn the subscription NFT"
    echo "   - Return all remaining tokens to subscriber"
    echo "   - Close the subscription contract"
    echo ""
    echo "   Run: submit_tx subscriber_withdraw.tx.signed"
    
    # Show transaction details
    cardano-cli conway transaction view --tx-file subscriber_withdraw.tx.signed
else
    echo "ERROR: Failed to build transaction"
    echo "Common issues:"
    echo "  - Subscription not yet expired"
    echo "  - Missing mint policy script"
    echo "  - Invalid redeemer format"
fi 