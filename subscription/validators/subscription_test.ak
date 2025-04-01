use aiken/hash
use aiken/interval.{Finite, Interval, IntervalBound, PositiveInfinity}
use aiken/list
use aiken/transaction.{
  Output, OutputReference, ScriptContext, ScriptPurpose, Transaction,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKey, VerificationKeyHash,
}
use aiken/transaction/value
use subscription/lib/subscription.{
  MintAction, SubscriptionDatum, day_in_ms, penalty_period_1, penalty_period_2,
  subscription_amount, subscription_period,
}
use subscription/validators/subscription

fn setup_test_parameters() {
  let admin_key: ByteArray =
    #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  let talos_policy: ByteArray =
    #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd"
  let talos_asset: ByteArray = #"74616c6f73" // hex for "talos"

  let owner_key: VerificationKeyHash =
    #"beefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeaf"

  (admin_key, talos_policy, talos_asset, owner_key)
}

test early_withdrawal_with_30_percent_penalty() {
  let (admin_key, talos_policy, talos_asset, owner_key) = setup_test_parameters()

  // Start time and current time (5 days later)
  let start_time = 1000000
  let current_time = start_time + 5 * day_in_ms

  // Datum
  let datum =
    SubscriptionDatum { owner: owner_key, start_time: start_time }

  // Expected amounts
  let admin_amount = subscription_amount * 30 / 100 // 3000
  let user_amount = subscription_amount * 70 / 100 // 7000

  // Create test outputs
  let admin_output =
    Output {
      address: Address {
        payment_credential: VerificationKey(admin_key),
        stake_credential: None,
      },
      value: value.from_asset(talos_policy, talos_asset, admin_amount),
      datum: None,
      reference_script: None,
    }

  let user_output =
    Output {
      address: Address {
        payment_credential: VerificationKey(owner_key),
        stake_credential: None,
      },
      value: value.from_asset(talos_policy, talos_asset, user_amount),
      datum: None,
      reference_script: None,
    }

  // Create burn entry for NFT
  let self_policy = #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  let nft_name = #"737562736372697074696f6e5f6e6674" // hex for "subscription_nft"
  let mint_policy =
    value.from_asset(self_policy, nft_name, -1)

  // Build the transaction
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [admin_output, user_output],
      fee: value.zero(),
      mint: mint_policy,
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(current_time),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: PositiveInfinity,
          is_inclusive: False,
        },
      },
      extra_signatories: [owner_key],
      redeemers: [],
      datums: [],
      id: #"",
    }

  // Create the script context
  let output_ref = OutputReference { transaction_id: #"", output_index: 0 }
  let ctx =
    ScriptContext {
      purpose: ScriptPurpose.Spend(output_ref),
      transaction: tx,
    }

  // Test the spending validator
  subscription.spend_validator(
    admin_key,
    talos_policy,
    talos_asset,
  ).spend(datum, Void, ctx)
}

test late_withdrawal_with_no_penalty() {
  let (admin_key, talos_policy, talos_asset, owner_key) = setup_test_parameters()

  // Start time and current time (35 days later)
  let start_time = 1000000
  let current_time = start_time + 35 * day_in_ms

  // Datum
  let datum =
    SubscriptionDatum { owner: owner_key, start_time: start_time }

  // Expected amounts - no penalty after 30 days
  let user_amount = subscription_amount // 10000

  // Create test output
  let user_output =
    Output {
      address: Address {
        payment_credential: VerificationKey(owner_key),
        stake_credential: None,
      },
      value: value.from_asset(talos_policy, talos_asset, user_amount),
      datum: None,
      reference_script: None,
    }

  // Create burn entry for NFT
  let self_policy = #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  let nft_name = #"737562736372697074696f6e5f6e6674" // hex for "subscription_nft"
  let mint_policy =
    value.from_asset(self_policy, nft_name, -1)

  // Build the transaction
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [user_output],
      fee: value.zero(),
      mint: mint_policy,
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(current_time),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: PositiveInfinity,
          is_inclusive: False,
        },
      },
      extra_signatories: [owner_key],
      redeemers: [],
      datums: [],
      id: #"",
    }

  // Create the script context
  let output_ref = OutputReference { transaction_id: #"", output_index: 0 }
  let ctx =
    ScriptContext {
      purpose: ScriptPurpose.Spend(output_ref),
      transaction: tx,
    }

  // Test the spending validator
  subscription.spend_validator(
    admin_key,
    talos_policy,
    talos_asset,
  ).spend(datum, Void, ctx)
} 