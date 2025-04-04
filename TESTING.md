# TALOS Subscription Service Testing Guide

This document provides instructions for testing the TALOS Subscription Service on the Cardano preprod testnet.

## Prerequisites

Before testing, ensure you have:

1. Successfully deployed the validator and minting policy scripts to preprod (see [DEPLOYMENT.md](DEPLOYMENT.md))
2. Recorded the following information:
   - Transaction IDs for reference script UTxOs
   - Validator address from the blueprint
   - NFT policy ID from the blueprint
   - Wallet addresses with test funds
3. TALOS tokens on preprod (or use a test token with similar properties)
4. A funded wallet with the necessary signing keys

## Preparing Test Data

### Create Test Files

Create the necessary datum and redeemer files for testing:

```bash
# Make a directory for test files
mkdir -p test_files
cd test_files

# Set variables
MERCHANT_KEY_HASH=$(cardano-cli address key-hash --payment-verification-key-file merchant.vkey)
SUBSCRIBER_KEY_HASH=$(cardano-cli address key-hash --payment-verification-key-file subscriber.vkey)
CURRENT_SLOT=$(cardano-cli query tip --testnet-magic 1 | jq .slot)
SUBSCRIPTION_START=$CURRENT_SLOT
INTERVAL_LENGTH=2592000  # 30 days in seconds
SUBSCRIPTION_END=$((SUBSCRIPTION_START + INTERVAL_LENGTH))

# Create subscription datum
cat > subscription_datum.json << EOF
{
  "constructor": 0,
  "fields": [
    {"int": 1000000},                      // service_fee
    {"int": 300000},                       // penalty_fee
    {"int": $INTERVAL_LENGTH},             // interval_length
    {"int": $SUBSCRIPTION_START},          // subscription_start
    {"int": $SUBSCRIPTION_END},            // subscription_end
    {"int": $SUBSCRIPTION_END},            // original_subscription_end
    {"list": []},                          // installments
    {"bytes": "$MERCHANT_KEY_HASH"},       // merchant_key_hash
    {"bytes": "$SUBSCRIBER_KEY_HASH"}      // subscriber_key_hash
  ]
}
EOF

# Create subscribe mint redeemer
cat > mint_subscribe.json << EOF
{
  "constructor": 0,
  "fields": []
}
EOF

# Create cancel subscription redeemer
cat > unsubscribe_redeemer.json << EOF
{
  "constructor": 2,
  "fields": []
}
EOF

# Create burn NFT redeemer
cat > mint_burn.json << EOF
{
  "constructor": 1,
  "fields": []
}
EOF

# Create merchant withdraw redeemer
cat > merchant_withdraw_redeemer.json << EOF
{
  "constructor": 1,
  "fields": []
}
EOF

# Create extension redeemer
cat > extend_redeemer.json << EOF
{
  "constructor": 0,
  "fields": [
    {"int": 1}  // additional_intervals
  ]
}
EOF
```

## Test Scenarios

### Test Case 1: Create a Subscription

This test creates a new subscription by locking TALOS tokens and minting an NFT certificate.

```bash
# Set up environment variables
VALIDATOR_ADDRESS="addr_test1..."  # Your validator address from plutus.json
PAYMENT_ADDR=$(cat wallet/payment.addr)
TALOS_POLICY_ID="..."  # Your TALOS token policy ID
TALOS_ASSET_NAME="74616c6f73"  # "talos" in hex
NFT_POLICY_ID="..."  # Your NFT policy ID from plutus.json
MINT_POLICY_UTXO="YOUR_MINT_POLICY_UTXO#INDEX"
PAYMENT_UTXO="YOUR_PAYMENT_UTXO#INDEX"  # A UTxO with sufficient funds

# Create a unique subscription ID (simple example)
SUBSCRIPTION_ID=$(echo -n "sub$(date +%s)" | xxd -p)

# Build transaction
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $PAYMENT_UTXO \
  --tx-out "${VALIDATOR_ADDRESS}+2000000+1 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --tx-out-inline-datum-file subscription_datum.json \
  --mint "1 ${NFT_POLICY_ID}.${SUBSCRIPTION_ID}" \
  --mint-reference-tx-in-reference $MINT_POLICY_UTXO \
  --mint-reference-tx-in-redeemer-file mint_subscribe.json \
  --mint-plutus-script-v3 \
  --policy-id $NFT_POLICY_ID \
  --validity-interval-start $(cardano-cli query tip --testnet-magic 1 | jq .slot) \
  --required-signer-hash $SUBSCRIBER_KEY_HASH \
  --change-address $PAYMENT_ADDR \
  --out-file subscribe_tx.raw

# Sign and submit
cardano-cli conway transaction sign \
  --tx-body-file subscribe_tx.raw \
  --signing-key-file wallet/payment.skey \
  --out-file subscribe_tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file subscribe_tx.signed
```

### Verify Subscription

```bash
# Check UTxOs at validator address
cardano-cli query utxo --address $VALIDATOR_ADDRESS --testnet-magic 1

# Check NFT in subscriber's wallet
cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic 1
```

### Test Case 2: Early Withdrawal (with penalty)

This test performs an early withdrawal from the subscription within the penalty period.

```bash
# First, identify the script UTxO from the previous step
SCRIPT_UTXO="UTXO_FROM_VALIDATOR_ADDRESS#INDEX"
SUBSCRIPTION_UTXO="YOUR_SUBSCRIPTION_SCRIPT_UTXO#INDEX"
ADMIN_ADDRESS="addr_test1..."  # Address to receive penalties

# Build withdrawal transaction
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $SCRIPT_UTXO \
  --tx-in-reference-script-file $SUBSCRIPTION_UTXO \
  --tx-in-datum-file subscription_datum.json \
  --tx-in-redeemer-file unsubscribe_redeemer.json \
  --tx-out "${ADMIN_ADDRESS}+2000000+300000 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --tx-out "${PAYMENT_ADDR}+2000000+700000 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --mint "-1 ${NFT_POLICY_ID}.${SUBSCRIPTION_ID}" \
  --mint-reference-tx-in-reference $MINT_POLICY_UTXO \
  --mint-reference-tx-in-redeemer-file mint_burn.json \
  --mint-plutus-script-v3 \
  --policy-id $NFT_POLICY_ID \
  --required-signer-hash $SUBSCRIBER_KEY_HASH \
  --change-address $PAYMENT_ADDR \
  --out-file withdraw_tx.raw

# Sign and submit
cardano-cli conway transaction sign \
  --tx-body-file withdraw_tx.raw \
  --signing-key-file wallet/payment.skey \
  --out-file withdraw_tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file withdraw_tx.signed
```

### Verify Withdrawal

```bash
# Check that script UTxO is gone
cardano-cli query utxo --address $VALIDATOR_ADDRESS --testnet-magic 1

# Check that admin received penalty
cardano-cli query utxo --address $ADMIN_ADDRESS --testnet-magic 1

# Check that subscriber received refund
cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic 1

# Verify NFT was burned
cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic 1 | grep $SUBSCRIPTION_ID
```

### Test Case 3: Merchant Withdrawal

This test allows the merchant to claim their service fee.

```bash
# Create a new subscription first (repeat Test Case 1)
# Then perform a merchant withdrawal

# Build merchant withdrawal transaction
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $SCRIPT_UTXO \
  --tx-in-reference-script-file $SUBSCRIPTION_UTXO \
  --tx-in-datum-file subscription_datum.json \
  --tx-in-redeemer-file merchant_withdraw_redeemer.json \
  --tx-out "${MERCHANT_ADDRESS}+2000000+1000000 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --required-signer-hash $MERCHANT_KEY_HASH \
  --change-address $MERCHANT_ADDRESS \
  --out-file merchant_withdraw_tx.raw

# Sign and submit
cardano-cli conway transaction sign \
  --tx-body-file merchant_withdraw_tx.raw \
  --signing-key-file merchant/payment.skey \
  --out-file merchant_withdraw_tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file merchant_withdraw_tx.signed
```

### Test Case 4: Subscription Extension

This test extends an existing subscription by adding more intervals.

```bash
# Identify the existing subscription UTxO
SCRIPT_UTXO="UTXO_FROM_VALIDATOR_ADDRESS#INDEX"

# Create a new datum with extended subscription period
# This would typically involve reading the existing datum and modifying it
# Here we assume you have created an updated datum file called extended_datum.json

# Build extension transaction
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $PAYMENT_UTXO \
  --tx-in $SCRIPT_UTXO \
  --tx-in-reference-script-file $SUBSCRIPTION_UTXO \
  --tx-in-datum-file subscription_datum.json \
  --tx-in-redeemer-file extend_redeemer.json \
  --tx-out "${VALIDATOR_ADDRESS}+2000000+2 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --tx-out-inline-datum-file extended_datum.json \
  --required-signer-hash $SUBSCRIBER_KEY_HASH \
  --change-address $PAYMENT_ADDR \
  --out-file extend_tx.raw

# Sign and submit
cardano-cli conway transaction sign \
  --tx-body-file extend_tx.raw \
  --signing-key-file wallet/payment.skey \
  --out-file extend_tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file extend_tx.signed
```

### Test Case 5: Full-term Withdrawal (no penalty)

This test performs a withdrawal after the subscription period has ended.

```bash
# For testing purposes, you may need to wait until the subscription period ends
# Or you could modify the subscription datum to have an earlier end time for testing

# Build full-term withdrawal transaction 
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $SCRIPT_UTXO \
  --tx-in-reference-script-file $SUBSCRIPTION_UTXO \
  --tx-in-datum-file subscription_datum.json \
  --tx-in-redeemer-file unsubscribe_redeemer.json \
  --tx-out "${PAYMENT_ADDR}+2000000+1000000 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --mint "-1 ${NFT_POLICY_ID}.${SUBSCRIPTION_ID}" \
  --mint-reference-tx-in-reference $MINT_POLICY_UTXO \
  --mint-reference-tx-in-redeemer-file mint_burn.json \
  --mint-plutus-script-v3 \
  --policy-id $NFT_POLICY_ID \
  --required-signer-hash $SUBSCRIBER_KEY_HASH \
  --change-address $PAYMENT_ADDR \
  --validity-interval-start $SUBSCRIPTION_END \
  --out-file full_term_withdraw_tx.raw

# Sign and submit
cardano-cli conway transaction sign \
  --tx-body-file full_term_withdraw_tx.raw \
  --signing-key-file wallet/payment.skey \
  --out-file full_term_withdraw_tx.signed

cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file full_term_withdraw_tx.signed
```

## Common Testing Issues

### 1. Transaction Validation Errors

If you encounter validation errors, check:
- Datum format matches what the validator expects
- Redeemer action is correct
- Transaction validity interval is appropriate
- All required signatures are included
- Token amounts match what the validator expects

### 2. Script Execution Units

If the transaction fails due to execution unit limits:
```bash
# Analyze script cost
cardano-cli transaction build \
  [your-transaction-parameters] \
  --calculate-plutus-script-cost analysis.json

# Review the output
cat analysis.json
```

### 3. Time-related Issues

For time-dependent tests:
- Use `--validity-interval-start` to simulate different times
- Modify the subscription datum for testing different time periods
- Remember that slots on preprod might have different conversion to time than mainnet

## Systematic Testing Approach

For complete test coverage, follow this sequence:

1. Subscribe with valid parameters
2. Test merchant claim of first installment
3. Try extend subscription (positive test)
4. Try early withdrawal in different penalty tiers
5. Try merchant withdrawal (all funds)
6. Try full-term withdrawal (after subscription ends)
7. Test failure conditions:
   - Wrong signatures
   - Invalid token amounts
   - Time constraints violations

## Advanced Testing with Scripts

For more efficient testing, consider creating automation scripts in Python or JavaScript that:
- Generate appropriate datums and redeemers
- Submit transactions in sequence
- Verify results automatically
- Test edge cases systematically

Example of a simple Python testing framework is available in `scripts/test_subscription.py`.

## Next Steps

After successful testing on preprod:
1. Fix any issues found during testing
2. Document the test results
3. Prepare for mainnet deployment with production parameters

For any issues or questions during testing, refer to the error messages in the cardano-cli output or contact the TALOS development team.

## Successful Subscription Creation on Testnet

After extensive trial and error, we've successfully created a subscription on the preprod testnet. Here's the working approach:

### Basic Subscription Creation (Successful)

This command successfully creates a subscription by sending a TALOS token to the validator with datum:

```bash
# Ensure you have enough ADA and TALOS tokens in your UTxOs
TOKEN_UTXO="UTXO_WITH_TALOS_TOKENS"
ADA_UTXO="UTXO_WITH_ENOUGH_ADA"

# Build transaction
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $TOKEN_UTXO \
  --tx-in $ADA_UTXO \
  --tx-out "${VALIDATOR_ADDRESS}+2000000+1 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --tx-out-inline-datum-file data/subscription_datum.json \
  --change-address $PAYMENT_ADDR \
  --out-file tx.raw

# Sign the transaction
cardano-cli conway transaction sign \
  --tx-body-file tx.raw \
  --signing-key-file /path/to/payment.skey \
  --testnet-magic 1 \
  --out-file tx.signed

# Submit the transaction
cardano-cli conway transaction submit \
  --testnet-magic 1 \
  --tx-file tx.signed
```

This approach successfully creates a subscription by:
1. Sending 1 TALOS token to the validator script
2. Including 2 ADA minimum required value
3. Attaching the subscription datum with details

### Adding NFT Minting (in progress)

The full subscription flow should also mint an NFT certificate using the reference script. Based on our testing, the following issues need to be addressed:

1. **Reference Script Syntax**: Use `--mint-tx-in-reference` to specify the UTxO containing the reference script
2. **Redeemer Syntax**: Use `--mint-reference-tx-in-redeemer-file` (not `--mint-redeemer-file`) when using reference scripts
3. **Key Hash Format**: The key hash needs to be properly formatted as Base16 for `--required-signer-hash`
4. **Policy ID**: Include `--policy-id` explicitly for the reference minting script
5. **Collateral Input**: Add `--tx-in-collateral` to provide collateral for script execution

The NFT minting command would look something like:

```bash
cardano-cli conway transaction build \
  --testnet-magic 1 \
  --tx-in $TOKEN_UTXO \
  --tx-in $ADA_UTXO \
  --tx-in-collateral $COLLATERAL_UTXO \
  --tx-out "${VALIDATOR_ADDRESS}+2000000+1 ${TALOS_POLICY_ID}.${TALOS_ASSET_NAME}" \
  --tx-out-inline-datum-file data/subscription_datum.json \
  --mint "1 ${NFT_POLICY_ID}.${SUBSCRIPTION_ID}" \
  --mint-tx-in-reference $MINT_POLICY_UTXO \
  --mint-plutus-script-v3 \
  --mint-reference-tx-in-redeemer-file data/mint_subscribe.json \
  --policy-id $NFT_POLICY_ID \
  --required-signer-hash $PROPERLY_FORMATTED_KEY_HASH \
  --change-address $PAYMENT_ADDR \
  --out-file tx.raw
```

Further testing is needed to resolve the key hash format issue for the NFT minting functionality.

### Plan for NFT Minting Resolution

To resolve the NFT minting issues, we will:

1. **Fix Key Hash Format**: The subscriber key hash needs to be in the proper Base16 format for Cardano CLI. Possible solutions:
   - Convert the key hash from hex to proper Base16 format
   - Use the key file directly with `--required-signer` instead of the hash
   - Create a script that doesn't require signer verification for testing

2. **Test Reference Script Usage**: Ensure the reference script UTxO is correctly formatted and accessible

3. **Simplify for Testing**: If the full functionality continues to be challenging, we can separate the subscription and minting into two transactions for testing purposes.

### Verifying Subscription

To verify the subscription was created correctly:

```bash
# Check validator address for TALOS token
cardano-cli query utxo --address $VALIDATOR_ADDRESS --testnet-magic 1

# Check your address for remaining tokens
cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic 1
```

The validator UTxO should show the TALOS token locked with the subscription datum.

## Testing Subscription Functions

// ... existing code ... 