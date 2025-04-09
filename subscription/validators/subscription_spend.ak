use aiken/collection/list.{filter, foldl, find, length, head, is_empty}
use aiken/collection/dict
use aiken/collection/pairs.{Pair}
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound, contains, hull, between}
use cardano/address.{Address, Credential}
use cardano/transaction.{Transaction, OutputReference, Input, find_input, Output, InlineDatum}
use cardano/assets
use cardano/assets.{PolicyId}

//
//  Data Structures
//

/// A single installment schedule
pub type Installment {
    claimable_at: Int,
    claimable_amount: Int,
}

/// Main subscription datum
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

/// Redeemers for spending
pub type Action {
    Extend { additional_intervals: Int }
    MerchantWithdraw
    Unsubscribe
    SubscriberWithdraw
}

/// Constants / logic
pub const day_in_ms: Int = 86400000
pub const penalty_period_1: Int = 10 * day_in_ms
pub const penalty_period_2: Int = 20 * day_in_ms
pub const subscription_period: Int = 30 * day_in_ms
pub const subscription_amount: Int = 10000  // each "installment" is 10,000 TALOS

///
/// compute penalty: returns (admin_portion, subscriber_refund)
///
pub fn calculate_penalty(elapsed: Int) -> (Int, Int) {
    if elapsed < penalty_period_1 {
        (subscription_amount * 30 / 100, subscription_amount * 70 / 100)
    } else if elapsed < penalty_period_2 {
        (subscription_amount * 20 / 100, subscription_amount * 80 / 100)
    } else if elapsed < subscription_period {
        (subscription_amount * 10 / 100, subscription_amount * 90 / 100)
    } else {
        // fully used => admin=0, subscriber= subscription_amount
        (0, subscription_amount)
    }
}

/// For merchant actions: use LOWER bound of tx range
pub fn current_time_for_merchant(range: Interval<Int>) -> Int {
    let Interval { lower_bound, .. } = range
    expect IntervalBound { bound_type: Finite(t), .. } = lower_bound
    t
}

/// For subscriber actions: use UPPER bound of tx range
pub fn current_time_for_subscriber(range: Interval<Int>) -> Int {
    let Interval { upper_bound, .. } = range
    expect IntervalBound { bound_type: Finite(t), .. } = upper_bound
    t
}

/// Ensure only one script input is consumed => no double satisfaction
pub fn ensure_single_script_input(
    inputs: List<Input>,
    script_addr: Address
) -> Bool {
    let count = foldl(
        inputs,
        0,
        fn(i, acc) {
            if i.output.address == script_addr {
                acc + 1
            } else {
                acc
            }
        }
    )
    count == 1
}

/// Check exact payment in TALOS for a single address
pub fn verify_exact_payment(
    outputs: List<Output>,
    receiver: VerificationKeyHash,
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    expected_amount: Int
) -> Bool {
    let outs = filter(outputs, fn(o) {
        o.address.payment_credential == Credential.VerificationKey(receiver)
    })
    let total_paid = foldl(
        outs,
        0,
        fn(o, acc) {
            acc + assets.quantity_of(o.value, talos_policy_id, talos_asset_name)
        }
    )
    total_paid == expected_amount
}

/// If partner_cut == 0 => skip, else check exact payment to partner
pub fn partner_cut_check(
    outputs: List<Output>,
    partner: VerificationKeyHash,
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    cut: Int
) -> Bool {
    if cut == 0 {
        True
    } else {
        verify_exact_payment(outputs, partner, talos_policy_id, talos_asset_name, cut)
    }
}

/// verify NFT is burned (we expect -1 minted for final closure)
pub fn verify_nft_burning(mint, nft_policy_id: PolicyId) -> Bool {
    when assets.tokens(mint, nft_policy_id) |> dict.to_pairs() is {
        [Pair(_, amt)] -> amt == -1
        _ -> False
    }
}

/// Validate basic subscription datum
pub fn validate_subscription_datum(d: SubscriptionDatum) -> Bool {
    and {
        d.partner_percentage >= 0,
        d.partner_percentage <= 100,
        d.subscription_end > d.subscription_start
    }
}

/// Check if a transaction's validity interval is contained within subscription active range
pub fn check_subscription_active(d: SubscriptionDatum, tx_range: Interval<Int>) -> Bool {
    let s_interval = between(d.subscription_start, d.subscription_end)
    hull(tx_range, s_interval) == s_interval
}

/// The main spending validator
validator subscription_spend(
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,
    admin: VerificationKeyHash,
    // The subscription NFT policy ID
    nft_policy_id: PolicyId
) {
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

        // Must have a valid datum
        expect Some(datum) = datum_opt
        // partner_percentage in [0..100]
        expect datum.partner_percentage >= 0
        expect datum.partner_percentage <= 100

        // find the input for this script
        expect Some(Input { output_reference: _, output: old_output }) = find_input(inputs, input)
        let script_addr = old_output.address

        // only 1 input from this script => no double satisfaction
        expect True = ensure_single_script_input(inputs, script_addr)

        when redeemer is {

            //
            // 1) Extend
            //
            Extend { additional_intervals } -> {
                expect True = check_subscription_active(datum, validity_range)

                // Must have 1 continuing output at script
                let script_outs = filter(outputs, fn(o) { o.address == script_addr })
                expect 1 = length(script_outs)
                expect Some(new_output) = head(script_outs)
                expect InlineDatum(dat) = new_output.datum
                expect new_datum: SubscriptionDatum = dat

                // Verify only subscriber can do this
                let subSigned = foldl(
                    extra_signatories,
                    False,
                    fn(sig, acc) { acc || sig == datum.subscriber_key_hash }
                )
                expect True = subSigned

                // Basic checks
                expect True = validate_subscription_datum(new_datum)

                // Must actually deposit subscription_amount * additional_intervals
                // Ensure no partial or negative intervals
                expect additional_intervals > 0

                let old_talos = assets.quantity_of(old_output.value, talos_policy_id, talos_asset_name)
                let new_talos = assets.quantity_of(new_output.value, talos_policy_id, talos_asset_name)
                let required_diff = subscription_amount * additional_intervals
                expect new_talos == old_talos + required_diff

                // subscription_end advanced
                expect new_datum.subscription_end
                   == datum.subscription_end + (additional_intervals * datum.interval_length)

                // all other fields must remain unchanged
                and {
                    new_datum.original_subscription_end == datum.original_subscription_end,
                    new_datum.service_fee == datum.service_fee,
                    new_datum.penalty_fee == datum.penalty_fee,
                    new_datum.interval_length == datum.interval_length,
                    new_datum.subscription_start == datum.subscription_start,
                    new_datum.merchant_key_hash == datum.merchant_key_hash,
                    new_datum.subscriber_key_hash == datum.subscriber_key_hash,
                    new_datum.partner_key_hash == datum.partner_key_hash,
                    new_datum.partner_percentage == datum.partner_percentage,

                    // installments must grow by that many intervals
                    length(new_datum.installments)
                        == length(datum.installments) + additional_intervals,

                    // keep NFT
                    assets.quantity_of(new_output.value, nft_policy_id, #"") == 1
                }
            }

            //
            // 2) MerchantWithdraw
            //
            MerchantWithdraw -> {
                expect True = check_subscription_active(datum, validity_range)
                // Must have installments left
                expect datum.installments != []
                expect [due, ..remaining] = datum.installments

                // time check for that installment
                // "contains(validity_range, due.claimable_at)" => ensures the due time is in range
                let script_outs = filter(outputs, fn(o) { o.address == script_addr })

                when length(remaining) is {
                    // If no installments remain after this => burn NFT => final closure
                    0 -> {
                        // Only merchant can sign
                        let merchantSigned = foldl(
                            extra_signatories,
                            False,
                            fn(sig, acc) { acc || (sig == datum.merchant_key_hash) }
                        )
                        expect True = merchantSigned

                        // This installment must be claimable
                        expect True = contains(validity_range, due.claimable_at)

                        let total_due = due.claimable_amount
                        let partner_cut = (total_due * datum.partner_percentage) / 100
                        let merchant_cut = total_due - partner_cut
                        // verify sum
                        expect partner_cut + merchant_cut == total_due

                        // must see exact payment
                        expect True = verify_exact_payment(
                            outputs,
                            datum.merchant_key_hash,
                            talos_policy_id,
                            talos_asset_name,
                            merchant_cut
                        )
                        expect True = partner_cut_check(
                            outputs,
                            datum.partner_key_hash,
                            talos_policy_id,
                            talos_asset_name,
                            partner_cut
                        )

                        // must burn NFT => final end
                        expect True = verify_nft_burning(mint, nft_policy_id)
                        // no continuing script outputs
                        expect True = is_empty(script_outs)
                    }

                    // still installments remain
                    _ -> {
                        expect 1 = length(script_outs)
                        expect Some(new_output) = head(script_outs)
                        expect InlineDatum(nd) = new_output.datum
                        expect new_datum: SubscriptionDatum = nd

                        let merchantSigned = foldl(
                            extra_signatories,
                            False,
                            fn(sig, acc) { acc || (sig == datum.merchant_key_hash) }
                        )
                        expect True = merchantSigned

                        // time
                        expect True = contains(validity_range, due.claimable_at)

                        let total_due = due.claimable_amount
                        let partner_cut = (total_due * datum.partner_percentage) / 100
                        let merchant_cut = total_due - partner_cut
                        expect partner_cut + merchant_cut == total_due

                        expect True = verify_exact_payment(
                            outputs,
                            datum.merchant_key_hash,
                            talos_policy_id,
                            talos_asset_name,
                            merchant_cut
                        )
                        expect True = partner_cut_check(
                            outputs,
                            datum.partner_key_hash,
                            talos_policy_id,
                            talos_asset_name,
                            partner_cut
                        )

                        // keep NFT => no burn
                        let minted_pairs = assets.tokens(mint, nft_policy_id) |> dict.to_pairs()
                        or {
                            minted_pairs == [],
                            minted_pairs == [Pair(_, 0)]
                        }

                        and {
                            // update installments
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

                            assets.quantity_of(new_output.value, nft_policy_id, #"") == 1
                        }
                    }
                }
            }

            //
            // 3) Unsubscribe
            //
            Unsubscribe -> {
                let now = current_time_for_subscriber(validity_range)
                expect True = check_subscription_active(datum, validity_range)

                // only subscriber can do it
                let subscriberSigned = foldl(
                    extra_signatories,
                    False,
                    fn(sig, acc) { acc || (sig == datum.subscriber_key_hash) }
                )
                expect True = subscriberSigned

                let elapsed = now - datum.subscription_start
                let (admin_amount, user_amount) = calculate_penalty(elapsed)

                // must burn NFT
                expect True = verify_nft_burning(mint, nft_policy_id)

                // find outputs for admin, partner, subscriber
                let admin_out_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(admin)
                })
                let partner_out_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(datum.partner_key_hash)
                })
                let user_out_opt = find(outputs, fn(o) {
                    o.address.payment_credential == Credential.VerificationKey(datum.subscriber_key_hash)
                })

                let partner_cut = (admin_amount * datum.partner_percentage) / 100
                let final_admin_amount = admin_amount - partner_cut

                let so = filter(outputs, fn(o) { o.address == script_addr })
                when admin_amount is {
                    0 -> {
                        // then partner_cut=0
                        expect Some(user_out) = user_out_opt
                        and {
                            assets.quantity_of(user_out.value, talos_policy_id, talos_asset_name)
                                == user_amount,
                            is_empty(so)
                        }
                    }
                    _ -> {
                        expect Some(ad_out) = admin_out_opt
                        expect Some(u_out) = user_out_opt

                        let partner_ok = if partner_cut == 0 {
                            True
                        } else {
                            expect Some(p_out) = partner_out_opt
                            assets.quantity_of(p_out.value, talos_policy_id, talos_asset_name)
                                == partner_cut
                        }

                        and {
                            assets.quantity_of(ad_out.value, talos_policy_id, talos_asset_name)
                                == final_admin_amount,
                            assets.quantity_of(u_out.value, talos_policy_id, talos_asset_name)
                                == user_amount,
                            partner_ok,
                            is_empty(so)
                        }
                    }
                }
            }

            //
            // 4) SubscriberWithdraw
            //
            SubscriberWithdraw -> {
                let now = current_time_for_subscriber(validity_range)
                expect now >= datum.subscription_end

                expect datum.installments != []
                // only subscriber
                let subscriberSigned = foldl(
                    extra_signatories,
                    False,
                    fn(sig, acc) { acc || (sig == datum.subscriber_key_hash) }
                )
                expect True = subscriberSigned

                // must burn NFT
                expect True = verify_nft_burning(mint, nft_policy_id)

                let so = filter(outputs, fn(o) { o.address == script_addr })
                and {
                    verify_exact_payment(
                        outputs,
                        datum.subscriber_key_hash,
                        talos_policy_id,
                        talos_asset_name,
                        subscription_amount
                    ),
                    is_empty(so)
                }
            }
        }
    }

    else(_) {
        fail
    }
}

// Quick test
test subscription_active_test() {
    let test_interval = between(100, 100)
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
    check_subscription_active(d, test_interval) == True
}
