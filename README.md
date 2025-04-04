# TALOS Subscription Service

A Cardano smart contract implementation for subscription services using TALOS tokens, built with Aiken.

## Overview

This project implements a token-based subscription service on Cardano with the following features:

- Time-based subscription system using TALOS tokens
- NFT certificates for active subscriptions
- Prorated refund system with decreasing penalties
- Trustless, on-chain validation of all subscription operations
- Secure interval-based time validation

## Project Status ✅

The project has been successfully implemented and compiled with Aiken. All tests are passing.

### Completed:

- ✅ Core validator functionality with spending and minting logic
- ✅ Penalty-based early withdrawal system (30%, 20%, 10%, 0%)
- ✅ NFT certificate minting and burning
- ✅ Token distribution validation
- ✅ Unit tests
- ✅ Development environment setup
- ✅ Security improvements against time-travel attacks
- ✅ Enhanced code structure using logical blocks

### Next Steps:

- ✅ Testnet deployment and validation
- Parameter configuration for production
- Security audit
- User interface integration

## Contract Design

### Subscription Flow

1. **Subscribe**: User locks TALOS tokens and receives an NFT certificate
2. **Active Period**: Subscription remains active for 30 days
3. **Withdrawal Options**:
   - **Early withdrawal**: Subscription can be terminated early with a penalty
   - **Full term**: After 30 days, tokens can be withdrawn without penalty
   - **Merchant withdrawal**: Subscription fees can be claimed by the merchant

### Penalty Tiers

Early withdrawal incurs a penalty based on elapsed time:

- 0-10 days: 30% penalty
- 10-20 days: 20% penalty
- 20-30 days: 10% penalty
- 30+ days: 0% penalty (full refund)

Penalties are automatically distributed to an admin address.

### Security Features

- **Interval-based time validation**: Prevents time-travel attacks by requiring transaction validity intervals to be contained within subscription periods
- **Structured validation logic**: Clear separation between structural validation and business logic
- **Proper asset quantity validation**: Uses native Cardano asset quantity validation for accurate token accounting

## Project Structure

```
prorated-sub-service/
├── subscription/
│   ├── validators/
│   │   └── subscription_prorated.ak  # Main validator script with tests
│   ├── scripts/                  # Off-chain helper scripts
│   │   ├── subscribe.js          # Script to create subscription
│   │   └── withdraw.js           # Script to withdraw funds
│   ├── aiken.toml                # Project configuration
│   └── aiken.lock                # Dependency lock file
├── README.md                     # This file
├── SETUP.md                      # Environment setup guide
└── DEVELOPER.md                  # Technical details for developers
```

## Quick Start

1. **Setup Environment**:
   ```bash
   # Install Aiken
   curl -sSfL https://install.aiken-lang.org | bash
   ```

2. **Compile Contract**:
   ```bash
   cd subscription
   aiken check
   aiken build
   ```

3. **Generate Plutus Script**:
   ```bash
   aiken blueprint
   ```

For detailed setup instructions, see [SETUP.md](SETUP.md).
For technical details and developer information, see [DEVELOPER.md](DEVELOPER.md).

## Deployment to Cardano Preprod Testnet

To deploy the smart contract to the Cardano preprod testnet, follow these steps:

1. **Compile and Generate Script Files**:
   ```bash
   cd subscription
   aiken build
   aiken blueprint
   ```

2. **Create Properly Formatted Plutus Scripts**:
   
   You need to convert the raw CBOR hex data from `plutus.json` into properly formatted script files. Use the following Python script with the `cbor2` library:

   ```python
   import cbor2
   import binascii
   
   # Load your script CBOR data from plutus.json
   with open('plutus.bin', 'rb') as f:
      script_bytes = f.read()
   
   # Properly wrap the script for cardano-cli compatibility
   wrapped_cbor = cbor2.dumps(cbor2.loads(script_bytes))
   
   # Save the formatted script file
   with open('subscription.plutus', 'wb') as f:
      f.write(wrapped_cbor)
   
   # Repeat similar process for minting policy
   ```

3. **Prepare Wallet and Transaction**:
   
   Set up environment variables for your wallet address:
   ```bash
   PAYMENT_ADDR=$(cat wallet/payment.addr)
   ```

4. **Deploy Scripts as Reference Scripts**:
   
   Submit a transaction that includes the scripts as reference scripts:
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

5. **Verify Deployment**:
   
   After submission, verify your transaction on a Cardano testnet explorer like [Cardanoscan Preprod](https://preprod.cardanoscan.io/).

6. **Record Reference Script UTxOs**:
   
   Note the transaction ID and output indices where your reference scripts are stored for future interactions with the contract.

For detailed deployment instructions, including wallet setup and interaction examples, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Testing

For instructions on testing the deployed smart contract on the Cardano preprod testnet, see [TESTING.md](TESTING.md). The testing guide covers:

- Creating subscription test data
- Test scenarios for different contract actions
- Verification procedures
- Troubleshooting common issues
- Systematic testing approach

## Configuration

Before deployment, the following parameters need to be configured:

- `talos_policy_id`: TALOS token policy ID
- `talos_asset_name`: TALOS token asset name
- `admin`: Treasury wallet address for receiving penalties
- `nft_policy_id`: Policy ID for subscription NFTs

## License

This project is licensed under the MIT License - see the LICENSE file for details.
