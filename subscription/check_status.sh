#!/bin/bash

echo "=== AGENT Subscription Contract Status ==="
echo "========================================="
echo

# Load environment
source setup_env.sh

# Check if script UTxO exists
if [ ! -f "script_utxos.json" ]; then
    echo "ERROR: script_utxos.json not found"
    echo "Run: cardano-cli query utxo --address $SCRIPT_ADDR --mainnet --out-file script_utxos.json"
    exit 1
fi

# Get current datum
SCRIPT_TX_IN=$SCRIPT_TX
jq -r --arg k "$SCRIPT_TX_IN" '.[$k].inlineDatum' script_utxos.json > current_datum.json

if [ ! -s "current_datum.json" ] || [ "$(cat current_datum.json)" == "null" ]; then
    echo "No active subscription found at script address"
    exit 0
fi

# Parse datum values
SERVICE_FEE=$(jq '.fields[0].int' current_datum.json)
PENALTY_FEE=$(jq '.fields[1].int' current_datum.json)
INTERVAL_LENGTH=$(jq '.fields[2].int' current_datum.json)
SUB_START=$(jq '.fields[3].int' current_datum.json)
SUB_END=$(jq '.fields[4].int' current_datum.json)
ORIGINAL_END=$(jq '.fields[5].int' current_datum.json)
INSTALLMENTS=$(jq '.fields[6].list | length' current_datum.json)
MERCHANT_HASH=$(jq -r '.fields[7].bytes' current_datum.json)
SUBSCRIBER_HASH=$(jq -r '.fields[8].bytes' current_datum.json)
PARTNER_HASH=$(jq -r '.fields[9].bytes' current_datum.json)
PARTNER_PERCENTAGE=$(jq '.fields[10].int' current_datum.json)

# Get current values
CURRENT_LOVELACE=$(jq -r --arg k "$SCRIPT_TX_IN" '.[$k].value.lovelace' script_utxos.json)
CURRENT_AGENT=$(jq -r --arg k "$SCRIPT_TX_IN" --arg p "$AGENT_POLICY_ID" --arg n "$AGENT_ASSET_NAME" '.[$k].value[$p][$n]' script_utxos.json)
HAS_NFT=$(jq -r --arg k "$SCRIPT_TX_IN" --arg p "$POLICY_ID" --arg n "$ASSET_HEX" '.[$k].value[$p][$n]' script_utxos.json)

# Calculate time status
NOW=$(date +%s)
NOW_MS=$((NOW * 1000))
TIME_REMAINING=$((SUB_END/1000 - NOW))

echo "📊 CONTRACT STATE"
echo "-----------------"
echo "Script Address: ${SCRIPT_ADDR:0:30}..."
echo "Script UTxO: $SCRIPT_TX_IN"
echo

echo "💰 LOCKED VALUE"
echo "--------------"
echo "ADA: $(echo "scale=6; $CURRENT_LOVELACE / 1000000" | bc)"
echo "AGENT: $CURRENT_AGENT"
echo "NFT: $HAS_NFT AGENT_SUB_NFT"
echo

echo "📅 SUBSCRIPTION DETAILS"
echo "----------------------"
echo "Start: $(date -d @$((SUB_START/1000)) '+%Y-%m-%d %H:%M:%S')"
echo "End: $(date -d @$((SUB_END/1000)) '+%Y-%m-%d %H:%M:%S')"
echo "Original End: $(date -d @$((ORIGINAL_END/1000)) '+%Y-%m-%d %H:%M:%S')"
echo "Interval: $((INTERVAL_LENGTH / 86400 / 1000)) days"
echo "Service Fee: $SERVICE_FEE AGENT"
echo "Penalty Fee: $PENALTY_FEE AGENT"
echo

echo "👥 PARTICIPANTS"
echo "--------------"
echo "Merchant: $MERCHANT_HASH"
echo "Subscriber: $SUBSCRIBER_HASH"
echo "Partner: $PARTNER_HASH (${PARTNER_PERCENTAGE}%)"
echo

echo "💳 INSTALLMENTS"
echo "--------------"
echo "Total: $INSTALLMENTS"
if [ "$INSTALLMENTS" -gt "0" ]; then
    for i in $(seq 0 $((INSTALLMENTS - 1))); do
        CLAIM_AT=$(jq ".fields[6].list[$i].fields[0].int" current_datum.json)
        CLAIM_AMOUNT=$(jq ".fields[6].list[$i].fields[1].int" current_datum.json)
        if [ "$NOW_MS" -ge "$CLAIM_AT" ]; then
            STATUS="✅ Claimable"
        else
            WAIT=$((($CLAIM_AT - NOW_MS) / 1000))
            STATUS="⏳ Wait ${WAIT}s"
        fi
        echo "  $((i+1)). $CLAIM_AMOUNT AGENT - $STATUS"
    done
else
    echo "  None - Run test_1_extend.sh to add installments"
fi
echo

echo "🎯 AVAILABLE ACTIONS"
echo "-------------------"
if [ "$TIME_REMAINING" -gt "0" ]; then
    echo "✅ Subscription Active (${TIME_REMAINING}s remaining)"
    echo "   1. Extend - Add more installments (test_1_extend.sh)"
    if [ "$INSTALLMENTS" -gt "0" ]; then
        echo "   2. MerchantWithdraw - Claim installments (test_2_merchant_withdraw.sh)"
    fi
    echo "   3. Unsubscribe - Cancel early (test_3_unsubscribe.sh)"
else
    echo "⏰ Subscription Expired"
    echo "   4. SubscriberWithdraw - Reclaim remaining tokens (test_4_subscriber_withdraw.sh)"
fi
echo

echo "📝 NEXT STEPS"
echo "------------"
if [ "$INSTALLMENTS" -eq "0" ]; then
    echo "1. Run: ./test_1_extend.sh"
    echo "   This will add an installment so merchant can withdraw"
elif [ "$INSTALLMENTS" -gt "0" ] && [ "$NOW_MS" -ge "$(jq '.fields[6].list[0].fields[0].int' current_datum.json)" ]; then
    echo "1. Run: ./test_2_merchant_withdraw.sh"
    echo "   Merchant can claim their installment"
else
    echo "1. Wait for installment to become claimable, or"
    echo "2. Test early cancellation with ./test_3_unsubscribe.sh"
fi 