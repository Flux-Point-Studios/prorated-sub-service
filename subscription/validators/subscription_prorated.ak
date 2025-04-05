use aiken/collection/list.{filter, has, foldl, is_empty, length, head, find, foldl as list_foldl}
use aiken/collection/dict
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound, contains, hull, between}
use cardano/address.{Address, Credential}
use cardano/transaction.{Output, OutputReference, Transaction, Input, find_input, InlineDatum}
use cardano/assets
use cardano/assets.{PolicyId}

//-------------------------------------
// Subscription Datum & Types
//-------------------------------------

/// Data structure representing a single payment installment.
pub type Installment {
    claimable_at: Int,
    claimable_amount: Int,
}

/// Main datum structure for the subscription contract.
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
    partner_key_hash: VerificationKeyHash,
    partner_percentage: Int,
}

/// Actions that can be performed on the subscription.
pub type Action {
    Extend { additional_intervals: Int }
    MerchantWithdraw
    Unsubscribe
    SubscriberWithdraw
}

/// Actions for minting the subscription NFT.
pub type MintAction {
    Subscribe
    CancelSubscription
}

//-------------------------------------
// Constants & Penalty Calculation
//-------------------------------------

pub const day_in_ms: Int = 86400000  // 24 * 60 * 60 * 1000
pub const penalty_period_1: Int = 10 * day_in_ms
pub const penalty_period_2: Int = 20 * day_in_ms
pub const subscription_period: Int = 30 * day_in_ms
pub const subscription_amount: Int = 10000

/// Calculate penalty for early unsubscription.
/// Returns (admin_amount, subscriber_refund).
pub fn calculate_penalty(elapsed: Int) -> (Int, Int) {
    if elapsed < penalty_period_1 {
        (subscription_amount * 30 / 100, subscription_amount * 70 / 100)
    } else if elapsed < penalty_period_2 {
        (subscription_amount * 20 / 100, subscription_amount * 80 / 100)
    } else if elapsed < subscription_period {
        (subscription_amount * 10 / 100, subscription_amount * 90 / 100)
    } else {
        // subscription fully used => admin gets 0
        (0, subscription_amount)
    }
}

//-------------------------------------
// Time-Handling Helpers
//-------------------------------------

/// For merchant actions: use the LOWER bound so a malicious merchant
/// cannot push time forward artificially.
pub fn current_time_for_merchant(tx_range: Interval<Int>) -> Int {
    let Interval { lower_bound, .. } = tx_range
    expect IntervalBound { bound_type: Finite(t), .. } = lower_bound
    t
}

/// For subscriber actions: use the UPPER bound so a malicious subscriber
/// cannot push time backward artificially.
pub fn current_time_for_subscriber(tx_range: Interval<Int>) -> Int {
    let Interval { upper_bound, .. } = tx_range
    expect IntervalBound { bound_type: Finite(t), .. } = upper_bound
    t
}

//-------------------------------------
// Double Satisfaction Mitigation
//-------------------------------------

/// Ensure there's only one input from THIS script in the entire transaction,
/// preventing multi-input double satisfaction attacks.
pub fn ensure_single_script_input(
    inputs: List<Input>,
    script_address: Address
) -> Bool {
    let count = list_foldl(
        inputs,
        0,
        fn(i, acc) {
            if i.output.address == script_address {
                acc + 1
            } else {
                acc
            }
        }
    )
    count == 1
}

//-------------------------------------
// Output Value Checking
//-------------------------------------

/// Verify that EXACT payment in TALOS is made to a single address,
/// preventing double satisfaction (no single output can fulfill multiple inputs).
pub fn verify_exact_payment(
    outputs: List<Output>,
    receiver_key_hash: VerificationKeyHash,
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    expected_amount: Int
) -> Bool {
    // Filter outputs to the given receiver
    let receiver_outputs = filter(outputs, fn(o) {
        o.address.payment_credential == Credential.VerificationKey(receiver_key_hash)
    })

    // Sum all TALOS tokens in these outputs
    let total_paid = foldl(
        receiver_outputs,
        0,
        fn(out, acc) {
            acc + assets.quantity_of(out.value, talos_policy_id, talos_asset_name)
        }
    )

    // Must match exactly
    total_paid == expected_amount
}

/// Helper to handle partner's portion if > 0.
/// If zero, no partner output is required.
pub fn partner_cut_check(
    outputs: List<Output>,
    partner_hash: VerificationKeyHash,
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    partner_cut: Int
) -> Bool {
    if partner_cut == 0 {
        True
    } else {
        verify_exact_payment(outputs, partner_hash, talos_policy_id, talos_asset_name, partner_cut)
    }
}

//-------------------------------------
// NFT Burning Check
//-------------------------------------

/// Check if the script's subscription NFT is being burned in the transaction
pub fn verify_nft_burning(
    mint,
    nft_policy_id: PolicyId
) -> Bool {
    when assets.tokens(mint, nft_policy_id) |> dict.to_pairs() is {
        [Pair(_token_name, amount)] -> amount == -1
        _ -> False
    }
}

//-------------------------------------
// Additional Validations
//-------------------------------------

/// Validate subscription datum upon creation/extension:
/// 1) partner_percentage in [0..100]
/// 2) subscription_end > subscription_start
pub fn validate_subscription_datum(d: SubscriptionDatum) -> Bool {
    and {
        d.partner_percentage >= 0,
        d.partner_percentage <= 100,
        d.subscription_end > d.subscription_start
    }
}

/// Check if a transaction validity interval is entirely within the subscription period.
/// Typically used for actions that must happen while active.
pub fn check_subscription_active(datum: SubscriptionDatum, tx_range: Interval<Int>) -> Bool {
    let s_interval = between(datum.subscription_start, datum.subscription_end)
    hull(tx_range, s_interval) == s_interval
}

//-------------------------------------
// Main Validator
//-------------------------------------
validator subscription(
    // CIP-57 parameters
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    admin: VerificationKeyHash,
    nft_policy_id: PolicyId
) {
    // SPEND branch (consuming the subscription UTXO)
    spend(
        datum_opt: Option<SubscriptionDatum>,
        redeemer: Action,
        input: OutputReference,
        tx: Transaction
    ) {
        let Transaction {
            inputs,
            outputs,
            validity_range,
            extra_signatories,
            mint,
            ..
        } = tx

        // Datum must be present
        expect Some(datum) = datum_opt

        // Check partner % in [0..100]
        expect datum.partner_percentage >= 0
        expect datum.partner_percentage <= 100

        // Find the specific input for this script
        expect Some(Input { output_reference: _, output: old_output }) = find_input(inputs, input)
        let script_addr = old_output.address

        // Mitigate double satisfaction: only 1 input from this script
        expect True = ensure_single_script_input(inputs, script_addr)

        // Dispatch logic based on the redeemer
        when redeemer is {
            Extend { additional_intervals } -> {
                // Must remain within subscription
                expect True = check_subscription_active(datum, validity_range)

                let script_outputs = filter(outputs, fn(o) { o.address == script_addr })
                expect 1 = length(script_outputs)
                expect Some(new_output) = head(script_outputs)
                expect InlineDatum(new_data) = new_output.datum
                expect new_datum: SubscriptionDatum = new_data

                and {
                    // Only subscriber can extend
                    has(extra_signatories, datum.subscriber_key_hash),

                    // Validate new fields
                    validate_subscription_datum(new_datum),

                    // The subscription_end must be advanced by additional_intervals
                    new_datum.subscription_end
                        == datum.subscription_end + (additional_intervals * datum.interval_length),

                    // Keep all other fields
                    new_datum.original_subscription_end == datum.original_subscription_end,
                    new_datum.service_fee == datum.service_fee,
                    new_datum.penalty_fee == datum.penalty_fee,
                    new_datum.interval_length == datum.interval_length,
                    new_datum.subscription_start == datum.subscription_start,
                    new_datum.merchant_key_hash == datum.merchant_key_hash,
                    new_datum.subscriber_key_hash == datum.subscriber_key_hash,
                    new_datum.partner_key_hash == datum.partner_key_hash,
                    new_datum.partner_percentage == datum.partner_percentage,

                    // Increase the number of installments by additional_intervals
                    length(new_datum.installments)
                        == length(datum.installments) + additional_intervals,

                    // NFT must remain exactly once
                    assets.quantity_of(new_output.value, nft_policy_id, #"") == 1
                }
            }

            MerchantWithdraw -> {
                // Must remain an active subscription
                expect True = check_subscription_active(datum, validity_range)

                // Must have at least one installment
                expect datum.installments != []
                expect [due, ..remaining] = datum.installments

                let script_outputs = filter(outputs, fn(o) { o.address == script_addr })
                expect 1 = length(script_outputs)
                expect Some(new_output) = head(script_outputs)
                expect InlineDatum(new_data) = new_output.datum
                expect new_datum: SubscriptionDatum = new_data

                // Compute how much is due (one installment)
                let total_due = due.claimable_amount
                let partner_cut = (total_due * datum.partner_percentage) / 100
                let merchant_cut = total_due - partner_cut

                and {
                    // Only merchant can trigger this
                    has(extra_signatories, datum.merchant_key_hash),

                    // This installment must be claimable
                    contains(validity_range, due.claimable_at),

                    // Transition to new datum with the first installment removed
                    new_datum.installments == remaining,
                    new_datum.service_fee == datum.service_fee,
                    new_datum.penalty_fee == datum.penalty_fee,
                    new_datum.interval_length == datum.interval_length,
                    new_datum.subscription_start == datum.subscription_start,
                    new_datum.subscription_end == datum.subscription_end,
                    new_datum.original_subscription_end == datum.original_subscription_end,
                    new_datum.merchant_key_hash == datum.merchant_key_hash,
                    new_datum.subscriber_key_hash == datum.subscriber_key_hash,
                    new_datum.partner_key_hash == datum.partner_key_hash,
                    new_datum.partner_percentage == datum.partner_percentage,

                    // Pay merchant & partner exactly
                    verify_exact_payment(
                        outputs,
                        datum.merchant_key_hash,
                        talos_policy_id,
                        talos_asset_name,
                        merchant_cut
                    ),
                    partner_cut_check(
                        outputs,
                        datum.partner_key_hash,
                        talos_policy_id,
                        talos_asset_name,
                        partner_cut
                    ),

                    // NFT remains
                    assets.quantity_of(new_output.value, nft_policy_id, #"") == 1
                }
            }

            Unsubscribe -> {
                // Use UPPER bound for subscriber action
                let current_time = current_time_for_subscriber(validity_range)

                // Must still be within subscription
                expect True = check_subscription_active(datum, validity_range)

                // Only subscriber can do this
                expect True = has(extra_signatories, datum.subscriber_key_hash)

                // Compute penalty
                let elapsed = current_time - datum.subscription_start
                let (admin_amount, user_amount) = calculate_penalty(elapsed)

                // NFT must be burned
                expect True = verify_nft_burning(mint, nft_policy_id)

                // Payment distribution
                let admin_output_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(admin)
                })
                let partner_output_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(datum.partner_key_hash)
                })
                let user_output_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(datum.subscriber_key_hash)
                })

                let partner_cut = (admin_amount * datum.partner_percentage) / 100
                let final_admin_amount = admin_amount - partner_cut

                let script_outputs = filter(outputs, fn(o) { o.address == script_addr })
                when admin_amount is {
                    0 -> {
                        // Then partner_cut is 0
                        expect Some(user_output) = user_output_opt
                        and {
                            assets.quantity_of(user_output.value, talos_policy_id, talos_asset_name)
                                == user_amount,
                            // No output left at the script
                            is_empty(script_outputs)
                        }
                    }
                    _ -> {
                        expect Some(admin_output) = admin_output_opt
                        expect Some(user_output) = user_output_opt

                        let partner_ok = if partner_cut == 0 {
                            True
                        } else {
                            expect Some(p_out) = partner_output_opt
                            assets.quantity_of(
                                p_out.value,
                                talos_policy_id,
                                talos_asset_name
                            ) == partner_cut
                        }

                        and {
                            // Admin must receive final_admin_amount
                            assets.quantity_of(
                                admin_output.value,
                                talos_policy_id,
                                talos_asset_name
                            ) == final_admin_amount,

                            // User gets remainder
                            assets.quantity_of(
                                user_output.value,
                                talos_policy_id,
                                talos_asset_name
                            ) == user_amount,

                            partner_ok,
                            // No script output left
                            is_empty(script_outputs)
                        }
                    }
                }
            }

            SubscriberWithdraw -> {
                // Also a subscriber action => use UPPER bound
                let current_time = current_time_for_subscriber(validity_range)

                // Must only happen after subscription_end
                expect current_time >= datum.subscription_end

                // Must have installments
                expect datum.installments != []

                // Must require subscriber signature
                expect True = has(extra_signatories, datum.subscriber_key_hash)

                // NFT must be burned
                expect True = verify_nft_burning(mint, nft_policy_id)

                // Return entire locked subscription_amount
                let script_outputs = filter(outputs, fn(o) { o.address == script_addr })
                and {
                    verify_exact_payment(
                        outputs,
                        datum.subscriber_key_hash,
                        talos_policy_id,
                        talos_asset_name,
                        subscription_amount
                    ),
                    // No continuing output
                    is_empty(script_outputs)
                }
            }
        }
    }

    // MINT branch (the NFT policy)
    mint(redeemer: MintAction, policy_id: PolicyId, tx: Transaction) {
        let outputs = tx.outputs
        let mint = tx.mint

        let minted_assets = assets.tokens(mint, policy_id) |> dict.to_pairs()
        expect length(minted_assets) == 1
        expect [Pair(token_name, amount)] = minted_assets

        when redeemer is {
            Subscribe -> {
                // Exactly 1 NFT minted
                expect amount == 1

                // The script output that receives this NFT
                let script_outputs = filter(outputs, fn(o) {
                    assets.quantity_of(o.value, policy_id, token_name) == 1
                })
                expect 1 = length(script_outputs)
                expect Some(sub_output) = head(script_outputs)

                // Parse the new subscription datum
                expect InlineDatum(datum_data) = sub_output.datum
                expect new_datum: SubscriptionDatum = datum_data

                and {
                    // Ensure the SAME output has exactly subscription_amount in TALOS
                    assets.quantity_of(
                        sub_output.value,
                        talos_policy_id,
                        talos_asset_name
                    ) == subscription_amount,

                    // Ensure the new subscriber signs creation
                    has(tx.extra_signatories, new_datum.subscriber_key_hash),

                    // Validate the datum fields
                    validate_subscription_datum(new_datum)
                }
            }

            CancelSubscription -> {
                // Exactly 1 NFT burned
                expect amount == -1
                True
            }
        }
    }

    else(_) {
        fail
    }
}

//-------------------------------------
// Quick Test
//-------------------------------------
test subscription_is_active() {
    let interval = between(100, 100)
    let d = SubscriptionDatum {
        service_fee: 1000,
        penalty_fee: 500,
        interval_length: 30,
        subscription_start: 0,
        subscription_end: 200,
        original_subscription_end: 200,
        installments: [],
        merchant_key_hash: #"deadbeef",
        subscriber_key_hash: #"deadbeef",
        partner_key_hash: #"deadbeef",
        partner_percentage: 0
    }

    check_subscription_active(d, interval) == True
}
