#!/bin/bash

echo "=== Test 1: Extend Subscription (Add Installment) ==="
echo "This will add another 10,000 AGENT and extend subscription by 30 days"
echo

# Load environment and helpers
source setup_env.sh
source blockfrost_query.sh

# 1. Get current script UTxO data
echo "1. Reading current script UTxO data..."
SCRIPT_TX_IN=$SCRIPT_TX
jq -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > old_datum.json

# 2. Parse current datum values
echo "2. Parsing current datum..."
IVL=$(jq -r '.fields[2].int' old_datum.json)           # interval_length: 2592000
OLD_END=$(jq -r '.fields[4].int' old_datum.json)       # subscription_end
NEW_END=$((OLD_END + IVL))                             # +30 days

echo "  - Current subscription end: $OLD_END"
echo "  - New subscription end: $NEW_END"

# 3. Create new installment
echo "3. Creating new installment..."
NOW_MS=$(($(date +%s%3N)))
CLAIM_AT_MS=$((NOW_MS + IVL))

jq -n --argjson at "$CLAIM_AT_MS" '{
    constructor: 0,
    fields: [ {int: $at}, {int: 10000} ]
}' > new_inst.json

# 4. Update datum with new installment
echo "4. Updating datum..."
jq --argjson inst "$(cat new_inst.json)" \
   --argjson newEnd "$NEW_END" '
    .fields[4].int = $newEnd |
    .fields[6].list += [$inst]
' old_datum.json > new_datum.json

# 5. Calculate datum hash
echo "5. Calculating new datum hash..."
cardano-cli conway transaction hash-script-data \
    --script-data-file new_datum.json > new_datum.hash
NEW_DHASH=$(cat new_datum.hash)
echo "  - New datum hash: $NEW_DHASH"

# 6. Create redeemer for Extend
echo "6. Creating Extend redeemer..."
cat > extend.redeemer.json <<EOF
{ "constructor": 0, "fields": [ { "int": 1 } ] }
EOF

# 7. Query subscriber UTxOs
echo "7. Querying subscriber UTxOs..."
SUB_ADDR=$(cat wallets/subscriber/payment.addr)
query_utxos "$SUB_ADDR" > sub_utxos.json

# Find UTxO with at least 10,000 AGENT
AGENT_UTXO=$(jq -r --arg policy "$AGENT_POLICY_ID" --arg name "$AGENT_ASSET_NAME" '
    .[] | select(.amount[].unit == ($policy + $name) and (.amount[] | select(.unit == ($policy + $name)).quantity | tonumber) >= 10000) | 
    .tx_hash + "#" + (.output_index | tostring)
' sub_utxos.json | head -1)

# Find collateral UTxO
COLLATERAL_TX=$(jq -r '.[] | select(.amount | length == 1 and .amount[0].unit == "lovelace" and (.amount[0].quantity | tonumber) >= 5000000) | 
    .tx_hash + "#" + (.output_index | tostring)
' sub_utxos.json | head -1)

echo "  - Agent UTxO: $AGENT_UTXO"
echo "  - Collateral: $COLLATERAL_TX"

# 8. Build value for script output
echo "8. Building transaction..."
NEW_VALUE="4000000 + 1 ${POLICY_ID}.${ASSET_HEX} + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"

# 9. Get protocol parameters
get_protocol_params

# 10. Build the Extend transaction
echo "9. Building Extend transaction..."
cardano-cli conway transaction build \
    --tx-in "$SCRIPT_TX_IN" \
    --tx-in "$AGENT_UTXO" \
    --tx-in-script-file "$SPEND_SCRIPT" \
    --tx-in-datum-file old_datum.json \
    --tx-in-redeemer-file extend.redeemer.json \
    --tx-in-collateral "$COLLATERAL_TX" \
    --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \
    --tx-out-datum-hash "$NEW_DHASH" \
    --change-address "$SUB_ADDR" \
    --required-signer wallets/subscriber/payment.skey \
    --out-file extend.txbody \
    --mainnet

if [ $? -eq 0 ]; then
    echo "10. Transaction built successfully!"
    
    # Sign transaction
    echo "11. Signing transaction..."
    cardano-cli conway transaction sign \
        --tx-body-file extend.txbody \
        --signing-key-file wallets/subscriber/payment.skey \
        --out-file extend.tx.signed \
        --mainnet
    
    echo "12. Transaction ready to submit!"
    echo "    Run: submit_tx extend.tx.signed"
    
    # Show transaction details
    cardano-cli conway transaction view --tx-file extend.tx.signed
else
    echo "ERROR: Failed to build transaction"
    echo "Check that:"
    echo "  - Subscriber has enough AGENT tokens"
    echo "  - All paths are correct"
    echo "  - Datum is properly formatted"
fi 