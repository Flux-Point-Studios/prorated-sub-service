# TALOS Subscription Service

A Cardano smart contract implementation for subscription services using TALOS tokens, built with Aiken.

## Overview

This project implements a token-based subscription service on Cardano with the following features:

- Time-based subscription system using TALOS tokens
- NFT certificates for active subscriptions
- Prorated refund system with decreasing penalties
- Trustless, on-chain validation of all subscription operations

## Project Status ✅

The project has been successfully implemented and compiled with Aiken. All tests are passing.

### Completed:

- ✅ Core validator functionality with spending and minting logic
- ✅ Penalty-based early withdrawal system (30%, 20%, 10%, 0%)
- ✅ NFT certificate minting and burning
- ✅ Token distribution validation
- ✅ Unit tests
- ✅ Development environment setup

### Next Steps:

- Testnet deployment and validation
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

## Project Structure

```
prorated-sub-service/
├── subscription/
│   ├── validators/
│   │   └── subscription_test.ak  # Main validator script with tests
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
   nix profile install github:aiken-lang/aiken
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

## Configuration

Before deployment, the following parameters need to be configured:

- `talos_policy_id`: TALOS token policy ID
- `talos_asset_name`: TALOS token asset name
- `admin`: Treasury wallet address for receiving penalties
- `nft_policy_id`: Policy ID for subscription NFTs

## License

This project is licensed under the MIT License - see the LICENSE file for details.
