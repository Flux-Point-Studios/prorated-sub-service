use aiken/collection/list.{filter, has}
use aiken/collection/dict
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/transaction.{Output, OutputReference, Transaction, Input, find_input, InlineDatum}
use cardano/assets.{PolicyId, AssetName}
use cardano/address.{Credential}

/// Data structure representing a single payment installment
pub type Installment {
    claimable_at: Int,
    claimable_amount: Int,
}

/// Main datum structure for the subscription contract
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

/// Actions that can be performed on the subscription
pub type Action {
    /// Extend subscription by adding more intervals
    Extend { additional_intervals: Int }
    /// Allow merchant to claim due installments
    MerchantWithdraw
    /// Early termination by subscriber
    Unsubscribe
    /// Allow subscriber to reclaim funds after subscription ends
    SubscriberWithdraw
}

/// Actions that can be performed when minting NFT tokens
pub type MintAction {
    /// Create a new subscription
    Subscribe
    /// Cancel an existing subscription
    CancelSubscription
}

/// Constants for the time periods and penalties
pub const day_in_ms: Int = 86400000 // 24 * 60 * 60 * 1000
pub const penalty_period_1: Int = 10 * day_in_ms // 10 days in ms
pub const penalty_period_2: Int = 20 * day_in_ms // 20 days in ms
pub const subscription_period: Int = 30 * day_in_ms // 30 days in ms
pub const subscription_amount: Int = 10000 

/// Check if a subscription is active at the given time
pub fn check_subscription(datum: SubscriptionDatum, now: Int) -> Bool {
    datum.subscription_start <= now && now <= datum.subscription_end
}

/// Get the token amount from an output for a specific asset
pub fn get_token_amount(output: Output, policy_id: PolicyId, asset_name: AssetName) -> Int {
  when list.find(dict.to_pairs(assets.tokens(output.value, policy_id)), fn(pair) {
    let Pair(name, _) = pair
    name == asset_name 
  }) is {
    Some(pair) -> {
      let Pair(_, amount) = pair
      amount
    }
    None -> 0
  }
}

/// Calculate penalty based on elapsed time
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

validator subscription {
  /// Handle spending from the subscription
  spend(datum_opt: Option<SubscriptionDatum>, redeemer: Action, input: OutputReference, tx: Transaction) {
    let Transaction { inputs, outputs, validity_range, extra_signatories, .. } = tx

    expect Some(datum) = datum_opt
    expect Some(Input{ output_reference: _, output: old_output }) = find_input(inputs, input)
    let script_addr = old_output.address
    let script_outputs = filter(outputs, fn (o: Output) { o.address == script_addr })
    // Get current time (lower bound of the validity range)
    let Interval { lower_bound, .. } = validity_range
    expect IntervalBound { bound_type: Finite(now), .. } = lower_bound

    when redeemer is {
      Extend { additional_intervals } -> {
        // Only subscriber can extend
        expect True = has(extra_signatories, datum.subscriber_key_hash)
        // There must still be an ongoing subscription (before original end)
        expect True = check_subscription(datum, now)
        // Ensure exactly one new output remains at the script address
        expect False = list.is_empty(script_outputs)
        expect 1 = list.length(script_outputs)
        expect Some(new_output) = list.head(script_outputs)
        // Verify the datum of the new output
        expect InlineDatum(data) = new_output.datum
        expect new_datum: SubscriptionDatum = data
        // Subscription end should be extended correctly
        expect new_datum.subscription_end == datum.subscription_end + additional_intervals * datum.interval_length
        expect new_datum.original_subscription_end == datum.original_subscription_end
        // Number of installments should increase by the added intervals
        expect list.length(new_datum.installments) == list.length(datum.installments) + additional_intervals
        True
      }
      MerchantWithdraw -> {
        // Only merchant can withdraw installments
        expect True = has(extra_signatories, datum.merchant_key_hash)
        // At least one installment is due
        expect datum.installments != [] 
        expect [due, ..remaining] = datum.installments
        expect now >= due.claimable_at
        // One new output must remain at script (subscription continues)
        expect 1 = list.length(script_outputs)
        expect Some(new_output) = list.head(script_outputs)
        expect InlineDatum(data) = new_output.datum
        expect new_datum: SubscriptionDatum = data
        // The new datum should have removed the claimed installment
        expect new_datum.installments == remaining
        True
      }
      Unsubscribe -> {
        // Only subscriber can unsubscribe (early terminate)
        expect True = has(extra_signatories, datum.subscriber_key_hash)
        // Subscription must still be active (before end)
        expect True = check_subscription(datum, now)
        
        // Calculate penalty based on elapsed time
        let elapsed = now - datum.subscription_start
        let (admin_amount, user_amount) = calculate_penalty(elapsed)
        
        // Define token policies and names
        let talos_policy_id: ByteArray = #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd" 
        let talos_asset_name: ByteArray = #"74616c6f73"
        let admin: ByteArray = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        
        // Verify the NFT is being burned
        let nft_policy_id = #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let nft_tokens = assets.tokens(tx.mint, nft_policy_id) |> dict.to_pairs()
        expect list.length(nft_tokens) == 1
        
        // Get the single asset and amount (discard token name)
        expect [Pair(_token_name, amount)] = nft_tokens
        expect amount == -1
        
        // Verify the penalty distribution
        let admin_output_opt = 
          list.find(outputs, fn(output) {
            output.address.payment_credential == Credential.VerificationKey(admin)
          })
          
        let user_output_opt =
          list.find(outputs, fn(output) {
            output.address.payment_credential == Credential.VerificationKey(datum.subscriber_key_hash)
          })
        
        // Admin output might not exist if penalty is 0
        when admin_amount is {
          0 -> {
            expect Some(user_output) = user_output_opt
            get_token_amount(user_output, talos_policy_id, talos_asset_name) == user_amount
          }
          _ -> {
            expect Some(admin_output) = admin_output_opt
            expect Some(user_output) = user_output_opt
            get_token_amount(admin_output, talos_policy_id, talos_asset_name) == admin_amount &&
            get_token_amount(user_output, talos_policy_id, talos_asset_name) == user_amount
          }
        }
      }
      SubscriberWithdraw -> {
        // Only subscriber can withdraw remaining funds after subscription end
        expect True = has(extra_signatories, datum.subscriber_key_hash)
        // Only allow after subscription period has ended
        expect now >= datum.subscription_end
        // There must be installments left unclaimed by merchant
        expect datum.installments != []
        // No output should remain (closing out subscription)
        expect True = list.is_empty(script_outputs)
        True
      }
    }
  }
  
  /// Handle minting of NFT tokens for subscription
  mint(
    redeemer: MintAction,
    policy_id: PolicyId,
    tx: Transaction,
  ) {
    let talos_policy_id: ByteArray = #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd" 
    let talos_asset_name: ByteArray = #"74616c6f73"
    
    let outputs = tx.outputs
    let mint = tx.mint
    
    let minted_assets = assets.tokens(mint, policy_id) |> dict.to_pairs()
    expect list.length(minted_assets) == 1
    expect [Pair(_token_name, amount)] = minted_assets
    
    when redeemer is {
      Subscribe -> {
        expect amount == 1
        list.any(outputs, fn(output) {
          get_token_amount(output, talos_policy_id, talos_asset_name) == subscription_amount
        })
      }
      CancelSubscription -> {
        expect amount == -1
        True
      }
    }
  }
  
  else(_) {
    fail
  }
}

/// Test if a subscription is active within its validity period
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
