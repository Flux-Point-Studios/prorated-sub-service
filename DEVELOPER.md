# TALOS Subscription Service - Developer Documentation

This document provides technical details about the TALOS Subscription Service smart contract implementation.

## Smart Contract Architecture

The TALOS subscription service is implemented as a Cardano smart contract written in Aiken. The contract consists of two main components:

1. **Spending Validator**: Controls how subscription funds can be spent
2. **Minting Policy**: Governs the creation and burning of subscription NFTs

### Key Data Structures

#### Installment

```aiken
pub type Installment {
    claimable_at: Int,
    claimable_amount: Int,
}
```

Represents a payment installment that can be claimed by the merchant.

#### SubscriptionDatum

```aiken
pub type SubscriptionDatum {
    service_fee: Int,
    penalty_fee: Int,
    interval_length: Int,
    subscription_start: Int,
    subscription_end: Int,
    original_subscription_end: Int,
    installments: List<Installment>,
    merchant_key_hash: VerificationKeyHash,
    subscriber_key_hash: VerificationKeyHash,
}
```

The primary datum structure stored with subscription UTXOs.

#### Actions

The contract supports two sets of actions:

```aiken
pub type Action {
    Extend { additional_intervals: Int }
    MerchantWithdraw
    Unsubscribe
    SubscriberWithdraw
}

pub type MintAction {
    Subscribe
    CancelSubscription
}
```

## Contract Logic

### Subscription Flow

1. **Subscribe**:
   - Mint a subscription NFT
   - Lock TALOS tokens with subscription datum
   - Record subscription start time

2. **Merchant Withdrawal**:
   - Merchant can claim due installments
   - Requires merchant signature
   - Subscription continues with remaining installments

3. **Extension**:
   - Subscriber can add more intervals
   - Updates subscription end date
   - Adds new installments

4. **Early Termination**:
   - Subscriber can unsubscribe before end date
   - Penalty fee calculated based on elapsed time
   - NFT burned, funds distributed with penalties

5. **Full-term Withdrawal**:
   - After subscription period ends, subscriber can withdraw remaining funds
   - No penalty applies
   - NFT burned

### Penalty Calculation

Penalties are calculated based on the elapsed time since subscription start:

```aiken
pub fn calculate_penalty(elapsed: Int) -> (Int, Int) {
  if elapsed < penalty_period_1 {
    (subscription_amount * 30 / 100, subscription_amount * 70 / 100)
  } else if elapsed < penalty_period_2 {
    (subscription_amount * 20 / 100, subscription_amount * 80 / 100)
  } else if elapsed < subscription_period {
    (subscription_amount * 10 / 100, subscription_amount * 90 / 100)
  } else {
    (0, subscription_amount)
  }
}
```

The function returns a tuple: (admin_amount, user_amount).

## Security Considerations

### Time-based Validation

The contract uses the transaction validity interval to validate the current time:

```aiken
let Interval { lower_bound, .. } = validity_range
expect IntervalBound { bound_type: Finite(now), .. } = lower_bound
```

This approach ensures that time calculations are based on the blockchain's view of time, not off-chain estimates.

### Signature Verification

All actions require appropriate signatures:
- Subscriber actions require the subscriber's signature
- Merchant actions require the merchant's signature

### Token Verification

The contract checks that tokens are properly distributed when a subscription is terminated:

```aiken
get_token_amount(admin_output, talos_policy_id, talos_asset_name) == admin_amount &&
get_token_amount(user_output, talos_policy_id, talos_asset_name) == user_amount
```

## Integration Guide

### Interacting with the Contract

To interact with the contract, you'll need to construct transactions that:

1. Provide appropriate script inputs
2. Include required signatures
3. Attach correct datum values
4. Satisfy the validator conditions

### Transaction Construction

For subscription creation:
1. Mint a subscription NFT (using the mint policy)
2. Create a UTXO at the script address with the subscription datum
3. Include the TALOS tokens in the UTXO

For withdrawal:
1. Spend the script UTXO with the appropriate action
2. Include a valid datum
3. Provide the required signature
4. Distribute tokens according to the contract rules

## Testing

The contract includes a test suite to verify core functionality:

```aiken
test subscription_active() {
  let now = 100
  let test_datum = SubscriptionDatum {
    service_fee: 1000,
    penalty_fee: 500,
    interval_length: 30,
    subscription_start: 0,
    subscription_end: 200,
    original_subscription_end: 200,
    installments: [],
    merchant_key_hash: #"deadbeef",
    subscriber_key_hash: #"deadbeef",
  }
  check_subscription(test_datum, now) == True
}
```

Additional test cases should be added to cover all contract paths.

## Deployment Configuration

Before deployment, update these constants in the validator:

```aiken
let talos_policy_id: ByteArray = #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd" 
let talos_asset_name: ByteArray = #"74616c6f73"
let admin: ByteArray = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
let nft_policy_id = #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
```

Replace these values with your actual production values. 