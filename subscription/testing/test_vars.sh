#!/bin/bash

# UTXOs from your deployment (reference scripts)
export SUBSCRIPTION_SCRIPT_UTXO="09c131fa97b5f341ee8afe46508420bfa9eedbd4250ad3dfd94fd0240a1b213a#0"
export MINT_POLICY_UTXO="09c131fa97b5f341ee8afe46508420bfa9eedbd4250ad3dfd94fd0240a1b213a#1"
export PAYMENT_UTXO="09c131fa97b5f341ee8afe46508420bfa9eedbd4250ad3dfd94fd0240a1b213a#2"

# Script hash/policy ID from plutus.json
export VALIDATOR_HASH="ebfc86e1117dee0d544ad158c932459db871849ec478234a9616f692"
export NFT_POLICY_ID="ebfc86e1117dee0d544ad158c932459db871849ec478234a9616f692"

# Get your payment address
export PAYMENT_ADDR="addr_test1vz0vfyc99rcycndayaz63jf2336mgkjyzgkjvrhvt50nrzcvjtplf"

# Use test TALOS or create your own token for testing
export TALOS_POLICY_ID="ca74fd781676cda239aed1a130fcc1484a39814429f3dd4ff6301c27"
export TALOS_ASSET_NAME="74616c6f73"  # "talos" in hex

# Get key hash for testing - replace with your actual key hash
export SUBSCRIBER_KEY_HASH="9ec4930528f04c4dbd2745a8c92a8c75b45a4122d260eec5d1f318b"

# We already created the validator address, so just set it directly
export VALIDATOR_ADDRESS="addr_test1wzn25h5eu5e9308ev6dwan066nhcqn3cuu3qeky3amejnpsrccywu"

# Hard-code a current slot for testing
export CURRENT_SLOT=90000000
