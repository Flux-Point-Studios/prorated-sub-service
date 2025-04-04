use aiken/collection/list.{filter, has, any}
use aiken/collection/dict
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound, contains, hull, between}
use cardano/transaction.{Output, OutputReference, Transaction, Input, find_input, InlineDatum}
use cardano/assets
use cardano/assets.{PolicyId}
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

/// Check if a transaction validity interval is contained within the subscription period
pub fn check_subscription(datum: SubscriptionDatum, tx_interval: Interval<Int>) -> Bool {
    let subscription_interval = between(datum.subscription_start, datum.subscription_end)
    hull(tx_interval, subscription_interval) == subscription_interval
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

/// Verify that an exact payment is made to prevent double satisfaction attacks
pub fn verify_exact_payment(
    outputs: List<Output>, 
    receiver_key_hash: VerificationKeyHash, 
    policy_id: ByteArray, 
    asset_name: ByteArray, 
    expected_amount: Int
) -> Bool {
    // Find all outputs to the receiver
    let receiver_outputs = 
        filter(outputs, fn(output) {
            output.address.payment_credential == Credential.VerificationKey(receiver_key_hash)
        })
    
    // Sum all TALOS token amounts in these outputs
    let total_paid = 
        list.foldl(
            receiver_outputs, 
            0, 
            fn(output, acc) {
                acc + assets.quantity_of(output.value, policy_id, asset_name)
            }
        )
    
    // Verify the exact amount was paid
    total_paid == expected_amount
}

/// Check if the NFT is being burned in the transaction
pub fn verify_nft_burning(mint, policy_id: PolicyId) -> Bool {
    when assets.tokens(mint, policy_id) |> dict.to_pairs() is {
        [Pair(_token_name, amount)] -> amount == -1
        _ -> False
    }
}

/// Main subscription validator, parameterized for flexible usage
validator subscription(
    /// Policy ID for the Talos asset (32-byte script hash)
    talos_policy_id: ByteArray,
    /// Asset name for the Talos token (e.g. \"74616c6f73\" for \"talos\")
    talos_asset_name: ByteArray,
    /// Verification key hash of the administrator (used in penalty distribution)
    admin: VerificationKeyHash,
    /// Policy ID for the subscription NFT
    nft_policy_id: PolicyId
) {
    /// Handle spending from the subscription
    spend(datum_opt: Option<SubscriptionDatum>, redeemer: Action, input: OutputReference, tx: Transaction) {
        let Transaction { inputs, outputs, validity_range, extra_signatories, mint, .. } = tx

        // Ensure the SubscriptionDatum exists in the spending input
        expect Some(datum) = datum_opt
        
        // Retrieve the input being spent (the old UTxO protected by this validator)
        expect Some(Input{ output_reference: _, output: old_output }) = find_input(inputs, input)
        
        let script_addr = old_output.address
        let script_outputs = filter(outputs, fn (o: Output) { o.address == script_addr })

        // Extract lower bound for time-sensitive operations
        let Interval { lower_bound, .. } = validity_range
        expect IntervalBound { bound_type: Finite(current_time), .. } = lower_bound

        when redeemer is {
            Extend { additional_intervals } -> {
                // Structural validations
                expect False = list.is_empty(script_outputs)
                expect 1 = list.length(script_outputs)
                expect Some(new_output) = list.head(script_outputs)
                expect InlineDatum(data) = new_output.datum
                expect new_datum: SubscriptionDatum = data
                
                and {
                    // Authorization: Only subscriber can extend
                    has(extra_signatories, datum.subscriber_key_hash),
                    
                    // Time validation: Must be within subscription period
                    check_subscription(datum, validity_range),
                    
                    // Data transition validation
                    new_datum.subscription_end == datum.subscription_end + additional_intervals * datum.interval_length,
                    new_datum.original_subscription_end == datum.original_subscription_end,
                    new_datum.service_fee == datum.service_fee,
                    new_datum.penalty_fee == datum.penalty_fee,
                    new_datum.interval_length == datum.interval_length,
                    new_datum.subscription_start == datum.subscription_start,
                    new_datum.merchant_key_hash == datum.merchant_key_hash,
                    new_datum.subscriber_key_hash == datum.subscriber_key_hash,
                    
                    // Number of installments should increase by the added intervals
                    list.length(new_datum.installments) == list.length(datum.installments) + additional_intervals,
                    
                    // Verify NFT is maintained in the new output
                    assets.quantity_of(new_output.value, nft_policy_id, #"") == 1,
                }
            }
            MerchantWithdraw -> {
                // Structural validations
                expect datum.installments != [] 
                expect [due, ..remaining] = datum.installments
                expect 1 = list.length(script_outputs)
                expect Some(new_output) = list.head(script_outputs)
                expect InlineDatum(data) = new_output.datum
                expect new_datum: SubscriptionDatum = data
                
                and {
                    // Authorization: Only merchant can withdraw installments
                    has(extra_signatories, datum.merchant_key_hash),
                    
                    // Time validation: At least one installment is due
                    contains(validity_range, due.claimable_at),
                    
                    // Datum transition validation
                    new_datum.installments == remaining,
                    new_datum.service_fee == datum.service_fee,
                    new_datum.penalty_fee == datum.penalty_fee,
                    new_datum.interval_length == datum.interval_length,
                    new_datum.subscription_start == datum.subscription_start,
                    new_datum.subscription_end == datum.subscription_end,
                    new_datum.original_subscription_end == datum.original_subscription_end,
                    new_datum.merchant_key_hash == datum.merchant_key_hash,
                    new_datum.subscriber_key_hash == datum.subscriber_key_hash,
                    
                    // Verify exact payment to merchant
                    verify_exact_payment(
                        outputs, 
                        datum.merchant_key_hash, 
                        talos_policy_id, 
                        talos_asset_name, 
                        due.claimable_amount
                    ),
                    
                    // Verify NFT is maintained in the new output
                    assets.quantity_of(new_output.value, nft_policy_id, #"") == 1,
                }
            }
            Unsubscribe -> {
                // Authorization: Only subscriber can unsubscribe (early terminate)
                expect True = has(extra_signatories, datum.subscriber_key_hash)
                
                // Time validation: Subscription must still be active
                expect True = check_subscription(datum, validity_range)
                
                // Calculate penalty based on elapsed time using lower bound
                let elapsed = current_time - datum.subscription_start
                let (admin_amount, user_amount) = calculate_penalty(elapsed)
                
                // Verify the NFT is being burned
                expect True = verify_nft_burning(mint, nft_policy_id)
                
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
                        and {
                            // Verify exact refund, not just minimum
                            assets.quantity_of(user_output.value, talos_policy_id, talos_asset_name) == user_amount,
                            // No output should remain at script address (subscription closing)
                            list.is_empty(script_outputs),
                        }
                    }
                    _ -> {
                        expect Some(admin_output) = admin_output_opt
                        expect Some(user_output) = user_output_opt
                        and {
                            // Verify exact distribution, not just minimum
                            assets.quantity_of(admin_output.value, talos_policy_id, talos_asset_name) == admin_amount,
                            assets.quantity_of(user_output.value, talos_policy_id, talos_asset_name) == user_amount,
                            // No output should remain at script address (subscription closing)
                            list.is_empty(script_outputs),
                        }
                    }
                }
            }
            SubscriberWithdraw -> {
                // Structural validations
                expect datum.installments != []
                
                and {
                    // Authorization: Only subscriber can withdraw remaining funds
                    has(extra_signatories, datum.subscriber_key_hash),
                    
                    // Time validation: Transaction time must be after subscription end
                    current_time >= datum.subscription_end,
                    
                    // Verify NFT is being burned
                    verify_nft_burning(mint, nft_policy_id),
                    
                    // Verify exact refund to subscriber
                    verify_exact_payment(
                        outputs, 
                        datum.subscriber_key_hash, 
                        talos_policy_id, 
                        talos_asset_name, 
                        subscription_amount
                    ),
                    
                    // No output should remain (closing out subscription)
                    list.is_empty(script_outputs),
                }
            }
        }
    }
    
    /// Handle minting of NFT tokens for subscription
    mint(
        redeemer: MintAction,
        policy_id: PolicyId,
        tx: Transaction,
    ) {
        let outputs = tx.outputs
        let mint = tx.mint
        
        // Obtain the tokens minted under this policy
        let minted_assets = assets.tokens(mint, policy_id) |> dict.to_pairs()
        expect list.length(minted_assets) == 1
        expect [Pair(token_name, amount)] = minted_assets
        
        when redeemer is {
            Subscribe -> {
                // Verify exactly one token is minted (not more, not less)
                expect amount == 1
                
                // Find script output that should contain the subscription datum
                let script_outputs = filter(outputs, fn(output) {
                    assets.quantity_of(output.value, policy_id, token_name) == 1
                })
                
                and {
                    // Only one output should have the NFT
                    list.length(script_outputs) == 1,
                    
                    // Verify subscription starts with correct TALOS amount
                    any(outputs, fn(output) {
                        assets.quantity_of(output.value, talos_policy_id, talos_asset_name) == subscription_amount
                    }),
                }
            }
            CancelSubscription -> {
                // Verify exactly one token is burned (not more, not less)
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
    let test_interval = between(100, 100)
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
    check_subscription(test_datum, test_interval) == True
}
