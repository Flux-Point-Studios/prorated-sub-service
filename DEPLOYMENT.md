# TALOS Subscription Service Deployment Guide

This document provides detailed instructions for deploying the TALOS Subscription Service to the Cardano preprod testnet.

## Prerequisites

1. **Cardano Node Access**
   - A running Cardano node connected to the preprod testnet (or a service like Demeter Run)
   - Updated `cardano-cli` (version compatible with Conway era)
   - Access to the preprod testnet

2. **Required Tools**
   - Python 3.8+ with `cbor2` library: `pip install cbor2`
   - Aiken v1.1.15+ for contract compilation
   - Wallet with preprod ADA for transaction fees

## Deployment Process

### Step 1: Compile the Contracts

First, compile your Aiken contracts:

```bash
cd subscription
aiken build
aiken blueprint
```

After compilation, you'll find the `plutus.json` file in the `.aiken` directory, which contains your compiled scripts.

### Step 2: Format Scripts for Cardano CLI

The raw CBOR output from Aiken needs proper wrapping for compatibility with `cardano-cli`. Create a Python script called `prepare_scripts.py`:

```python
import json
import cbor2
import binascii

# Load your script CBOR data from plutus.json
with open('.aiken/plutus.json', 'r') as f:
    blueprint = json.load(f)

# Extract the validator script
validator_cbor_hex = blueprint['validators'][0]['compiledCode']
validator_bytes = binascii.unhexlify(validator_cbor_hex)

# Extract the mint policy script
mint_policy_cbor_hex = blueprint['validators'][1]['compiledCode']  # Adjust index if needed
mint_policy_bytes = binascii.unhexlify(mint_policy_cbor_hex)

# Properly wrap the scripts for cardano-cli compatibility
wrapped_validator = cbor2.dumps(cbor2.loads(validator_bytes))
wrapped_mint_policy = cbor2.dumps(cbor2.loads(mint_policy_bytes))

# Save the formatted script files
with open('subscription.plutus', 'wb') as f:
    f.write(wrapped_validator)

with open('mint_policy.plutus', 'wb') as f:
    f.write(wrapped_mint_policy)

print("Scripts successfully formatted and saved.")
```

Run the script to generate properly formatted plutus files:

```bash
python prepare_scripts.py
```

### Step 3: Set Up Your Wallet

Set up a wallet for deployment:

```bash
# Generate keys if you don't have them already
cardano-cli address key-gen \
  --verification-key-file wallet/payment.vkey \
  --signing-key-file wallet/payment.skey

# Generate address
cardano-cli address build \
  --payment-verification-key-file wallet/payment.vkey \
  --testnet-magic 1 \
  --out-file wallet/payment.addr

# Set up environment variables
PAYMENT_ADDR=$(cat wallet/payment.addr)
```

Fund this address with preprod ADA (using a faucet or transfer).

### Step 4: Find a Suitable UTxO for the Transaction

Query your wallet for available UTxOs:

```bash
cardano-cli query utxo \
  --address $PAYMENT_ADDR \
  --testnet-magic 1
```

Choose a UTxO with sufficient funds (at least 50 ADA for the deployment).

### Step 5: Deploy Scripts as Reference Scripts

Create and sign a transaction that includes your scripts as reference scripts:

```bash
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in "YOUR_TX_INPUT_HERE#INDEX" \
  --tx-out "${PAYMENT_ADDR}+20000000" --tx-out-reference-script-file subscription.plutus \
  --tx-out "${PAYMENT_ADDR}+20000000" --tx-out-reference-script-file mint_policy.plutus \
  --change-address "${PAYMENT_ADDR}" \
  --out-file tx.raw

cardano-cli conway transaction sign \
  --tx-body-file tx.raw \
  --signing-key-file wallet/payment.skey \
  --out-file tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file tx.signed
```

Replace `YOUR_TX_INPUT_HERE#INDEX` with the TxID and index of your chosen UTxO.

### Step 6: Verify Deployment and Record Script UTxOs

After successful submission, query your wallet again to find the UTxOs containing your reference scripts:

```bash
cardano-cli query utxo \
  --address $PAYMENT_ADDR \
  --testnet-magic 1
```

Record the transaction ID and output indices where your reference scripts are stored (you'll need these for future interactions).

### Step 7: Record Script Addresses and Policy IDs

Extract script addresses and policy IDs from the blueprint:

```bash
# View and record the validator hash and policy ID
cat .aiken/plutus.json
```

Save these values for later use in off-chain code and user interface integration.

## Interacting with the Deployed Contract

### Subscription Creation

To create a subscription, you'll need to create a transaction that:

1. Uses the subscription validator address
2. Mints a subscription NFT
3. Provides the appropriate subscription datum
4. Includes the required TALOS tokens
5. Sets a valid transaction interval

Example transaction structure:

```bash
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in "YOUR_PAYMENT_UTXO#INDEX" \
  --tx-out "VALIDATOR_ADDRESS+MIN_ADA+TALOS_AMOUNT" \
  --tx-out-datum-hash-file subscription_datum.json \
  --mint "1 SUBSCRIPTION_NFT_POLICY_ID.ASSET_NAME" \
  --mint-script-file mint_policy.plutus \
  --mint-redeemer-file mint_redeemer.json \
  --validity-interval-start CURRENT_SLOT \
  --change-address $PAYMENT_ADDR \
  --out-file tx.raw
```

### Withdrawal

For subscription withdrawal, construct a transaction that:

1. Spends the script UTxO
2. Provides the withdrawal redeemer
3. Distributes tokens according to contract rules
4. Includes the required signatures

Example transaction structure:

```bash
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in "SCRIPT_UTXO#INDEX" \
  --tx-in-script-file subscription.plutus \
  --tx-in-datum-file subscription_datum.json \
  --tx-in-redeemer-file withdrawal_redeemer.json \
  --tx-out "ADMIN_ADDRESS+MIN_ADA+PENALTY_AMOUNT" \
  --tx-out "SUBSCRIBER_ADDRESS+MIN_ADA+REFUND_AMOUNT" \
  --mint "-1 SUBSCRIPTION_NFT_POLICY_ID.ASSET_NAME" \
  --mint-script-file mint_policy.plutus \
  --mint-redeemer-file burn_redeemer.json \
  --validity-interval-start CURRENT_SLOT \
  --change-address $PAYMENT_ADDR \
  --out-file tx.raw
```

## Troubleshooting

### Common Deployment Issues

1. **CBOR Format Errors**
   - Ensure the script wrapping is correct using the provided Python script
   - Check that you're using the correct CBOR library (`cbor2` recommended)

2. **Transaction Format Errors**
   - Verify the syntax for your version of `cardano-cli`
   - For Conway era, use the `+` sign between address and value: `--tx-out "${PAYMENT_ADDR}+20000000"`

3. **Reference Script Issues**
   - Verify the scripts were properly included in the UTxOs by examining the transaction on a blockchain explorer
   - Check that script reference UTxOs haven't been spent

4. **Transaction Fee Issues**
   - Ensure you have sufficient funds for the transaction fees
   - If using large scripts, you may need more ADA than expected

### Testing Your Deployment

After deployment, test your contract with simple subscription and withdrawal flows before proceeding to production integration.

## Next Steps

1. Update your off-chain code with the deployed script addresses and policy IDs
2. Configure your UI to interact with the deployed contracts
3. Run integration tests to verify all contract functions work correctly
4. Consider deploying to the mainnet after thorough testing

For further assistance with deployment or contract interactions, refer to the Cardano developer documentation or contact the TALOS team. 