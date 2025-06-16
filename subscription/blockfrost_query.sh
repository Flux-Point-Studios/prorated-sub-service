#!/bin/bash

# Load environment variables
source setup_env.sh
source .env

# Function to query UTxOs at an address
query_utxos() {
    local address=$1
    curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
        "$BLOCKFROST_API_URL/addresses/$address/utxos" | jq
}

# Function to get protocol parameters
get_protocol_params() {
    curl -s -H "project_id: $BLOCKFROST_PROJECT_ID" \
        "$BLOCKFROST_API_URL/epochs/latest/parameters" > pparams_blockfrost.json
    
    # Convert Blockfrost format to cardano-cli format
    jq '{
        minFeeA: .min_fee_a,
        minFeeB: .min_fee_b,
        maxTxSize: .max_tx_size,
        maxBlockBodySize: .max_block_body_size,
        maxBlockHeaderSize: .max_block_header_size,
        keyDeposit: .key_deposit,
        poolDeposit: .pool_deposit,
        minPoolCost: .min_pool_cost,
        priceMem: .price_mem,
        priceStep: .price_step,
        maxTxExecutionUnits: {
            memory: .max_tx_ex_mem,
            steps: .max_tx_ex_steps
        },
        maxBlockExecutionUnits: {
            memory: .max_block_ex_mem,
            steps: .max_block_ex_steps
        },
        maxValueSize: .max_val_size,
        collateralPercentage: .collateral_percent,
        maxCollateralInputs: .max_collateral_inputs,
        coinsPerUTxOByte: .coins_per_utxo_size
    }' pparams_blockfrost.json > pparams.json
}

# Function to submit transaction
submit_tx() {
    local tx_file=$1
    local tx_cbor=$(cat $tx_file | xxd -p | tr -d '\n')
    
    curl -X POST -H "project_id: $BLOCKFROST_PROJECT_ID" \
        -H "Content-Type: application/cbor" \
        "$BLOCKFROST_API_URL/tx/submit" \
        -d $tx_cbor
}

# Export functions
export -f query_utxos
export -f get_protocol_params
export -f submit_tx

echo "Blockfrost helper functions loaded!" 