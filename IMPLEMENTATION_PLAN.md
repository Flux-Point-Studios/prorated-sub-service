# TALOS Subscription Service Implementation Plan

## Project Structure

The Aiken project has been created with the following structure:

```
prorated-sub-service/
├── subscription/
│   ├── aiken.toml               # Project configuration
│   ├── validators/              # Smart contract validators
│   │   ├── subscription.ak      # Main validator script
│   │   └── subscription_test.ak # Test file for validator
│   ├── scripts/                 # Off-chain scripts for testing/deployment
│   │   ├── subscribe.js         # Script to create subscription
│   │   └── withdraw.js          # Script to withdraw funds
```

## Current Status

### Completed:

1. **Smart Contract (On-Chain)**
   - ✅ Datum structure for subscription
   - ✅ Spending validator for withdrawal logic with time-based penalties
   - ✅ Minting policy for subscription NFT
   - ✅ Unit tests for validator
   
2. **Off-Chain Code**
   - ✅ Sample script for subscription (locking tokens + minting NFT)
   - ✅ Sample script for withdrawal (with proper penalty calculation)

### To Do:

1. **Development Environment Setup**
   - ✅ Install Aiken
   - ⬜ Set up Cardano node or testing tools
   
2. **Compilation and Testing**
   - ⬜ Compile the validator
   - ⬜ Run the tests
   - ⬜ Generate the Plutus script
   
3. **Deployment**
   - ⬜ Testnet deployment
   - ⬜ Mainnet preparation

## Current Gaps and Research Needs

The following areas require further research or development:

1. **Parameter Definition**
   - Define the exact policy ID for $TALOS token
   - Define admin/treasury wallet address
   
2. **NFT Metadata**
   - Define the structure and content of NFT metadata for subscriptions
   - Determine how to include expiry information in metadata
   
3. **Reference Script Deployment**
   - Research optimal approach for reference script deployment on Cardano
   - Determine transaction size implications and fee optimization
   
4. **Frontend Integration**
   - Plan for integrating with wallet connectors (e.g., Nami, Eternl)
   - API design for subscription status verification
   
5. **Testing Strategy**
   - Edge case handling (e.g., network congestion affecting timing)
   - Integration testing with actual transactions
   
6. **Monitoring and Maintenance**
   - Plan for monitoring active subscriptions
   - Strategy for handling unclaimed deposits after expiry
   
7. **Security Audit**
   - Define scope for security audit
   - Identify potential vulnerabilities in design

## Next Steps

1. ⬜ Compile and test the validator
   ```
   cd subscription
   aiken check
   aiken build
   ```

2. ⬜ Generate the Plutus script and blueprint
   ```
   aiken blueprint
   ```

3. ⬜ Set up testnet environment
   - Install Cardano node or connect to testnet via Blockfrost
   - Create test wallets
   - Obtain test TALOS tokens

4. ⬜ Deploy reference script on testnet
   - Create reference UTXO with script
   - Update script constants with addresses and token IDs

5. ⬜ Test full subscription lifecycle on testnet
   - Create subscription
   - Verify NFT minting
   - Test early withdrawal with penalties
   - Test full-term withdrawal

6. ⬜ Review and audit the contract

7. ⬜ Prepare for mainnet deployment
   - Update documentation
   - Create mainnet deployment guide 