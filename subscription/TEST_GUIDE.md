# AGENT NFT Subscription Contract - Testing Guide

## Current Status
You have successfully completed the initial subscription setup:
- ✅ **Minted** 1 AGENT_SUB_NFT 
- ✅ **Locked** 10,000 AGENT tokens at the script address
- ✅ **Locked** 4 ADA minimum with the tokens
- 🚧 **Pending** Testing remaining use cases

## Prerequisites

### 1. Install Required Tools
```bash
# Update package list
sudo apt-get update

# Install required tools
sudo apt-get install -y jq bc

# Verify installations
cardano-cli --version  # Should show: cardano-cli 10.1.1.0
aiken --version        # Should show: aiken v1.1.17
jq --version          # Should show: jq-1.6 or higher
```

### 2. Fix Line Endings (if on Windows/WSL)
```bash
# Remove Windows carriage returns from scripts
for file in *.sh; do sed -i 's/\r$//' "$file"; done
```

### 3. Set Environment Variables
```bash
# Load environment variables
source setup_env.sh
```

## Test Scripts Overview

### 📊 check_status.sh
Shows the current state of your subscription contract:
- Locked value (ADA, AGENT, NFT)
- Subscription dates and status
- Available installments
- Possible actions

```bash
./check_status.sh
```

### 1️⃣ test_1_extend.sh
**Extend Subscription** - Adds another payment period
- Subscriber locks another 10,000 AGENT
- Extends subscription by 30 days
- Adds an installment that merchant can claim

```bash
./test_1_extend.sh
```

### 2️⃣ test_2_merchant_withdraw.sh
**Merchant Withdraw** - Allows merchant/partner to claim payments
- Requires at least one installment to exist
- Merchant claims their portion (considering partner percentage)
- Installment must be past its claimable timestamp

```bash
./test_2_merchant_withdraw.sh
```

### 3️⃣ test_3_unsubscribe.sh
**Early Cancellation** - Subscriber cancels before expiry
- Calculates prorated refund based on time used
- Deducts penalty fee from refund
- Burns the NFT and distributes tokens

```bash
./test_3_unsubscribe.sh
```

### 4️⃣ test_4_subscriber_withdraw.sh
**Subscriber Withdraw** - After subscription expires
- Only available after subscription_end timestamp
- Returns any remaining tokens to subscriber
- Burns the NFT and closes the contract

```bash
./test_4_subscriber_withdraw.sh
```

## Testing Workflow

### Scenario 1: Normal Subscription Flow
1. Check initial status: `./check_status.sh`
2. Extend subscription: `./test_1_extend.sh`
3. Wait for installment to be claimable (or proceed for testing)
4. Merchant withdraws: `./test_2_merchant_withdraw.sh`
5. Repeat extend/withdraw as needed

### Scenario 2: Early Cancellation
1. Check status: `./check_status.sh`
2. Cancel subscription: `./test_3_unsubscribe.sh`
3. Verify NFT burned and tokens distributed

### Scenario 3: Expired Subscription
1. Wait for subscription to expire (or test anyway)
2. Subscriber reclaims: `./test_4_subscriber_withdraw.sh`

## Using Blockfrost

The scripts use Blockfrost API for querying. Your API key is already configured in `.env`.

To manually query addresses:
```bash
source blockfrost_query.sh
query_utxos "addr1..."  # Replace with actual address
```

To submit a transaction:
```bash
submit_tx transaction.signed
```

## Troubleshooting

### "jq: command not found"
Install jq: `sudo apt-get install jq`

### "bc: command not found"  
Install bc: `sudo apt-get install bc`

### Script execution errors
1. Make scripts executable: `chmod +x *.sh`
2. Fix line endings: `sed -i 's/\r$//' *.sh`
3. Check paths are correct: `ls -la artifacts-mainnet/`

### Transaction building fails
1. Check you have sufficient funds
2. Verify all environment variables are set
3. Ensure protocol parameters are up to date
4. Check script hashes match on-chain

### Blockfrost errors
1. Verify API key is correct in `.env`
2. Check you're using mainnet key for mainnet
3. Ensure you haven't exceeded rate limits

## Next Steps

1. **First Priority**: Run `./test_1_extend.sh` to add an installment
2. **Then**: Test merchant withdrawal with `./test_2_merchant_withdraw.sh`
3. **Finally**: Test either early cancellation or expired withdrawal

## Contract Details

- **Script Address**: `addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf`
- **Current UTxO**: `85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0`
- **NFT Policy**: `efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb`
- **AGENT Policy**: `97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec`

## Important Notes

- Always check status before running tests
- Transactions on mainnet are irreversible
- Keep private keys secure
- Test timing constraints may be relaxed for testing purposes
- The contract enforces business logic - some actions require specific conditions 