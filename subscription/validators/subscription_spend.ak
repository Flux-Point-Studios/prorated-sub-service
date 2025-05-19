use aiken/collection/dict
use aiken/collection/list.{filter, find, foldl, head, is_empty, length}
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound, between, contains, hull}
use cardano/address.{Address, Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}

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

pub const subscription_amount: Int = 10000

// each installment is 10,000 agent

///
/// Compute penalty: returns (admin_portion, subscriber_refund)
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

/// Ensure only one script input => no double satisfaction
pub fn ensure_single_script_input(
  inputs: List<Input>,
  script_addr: Address,
) -> Bool {
  let count =
    foldl(
      inputs,
      0,
      fn(i, acc) {
        if i.output.address == script_addr {
          acc + 1
        } else {
          acc
        }
      },
    )
  count == 1
}

/// Check exact payment in agent for a single address
pub fn verify_exact_payment(
  outputs: List<Output>,
  receiver: VerificationKeyHash,
  agent_policy_id: ByteArray,
  agent_asset_name: ByteArray,
  expected_amount: Int,
) -> Bool {
  let outs =
    filter(
      outputs,
      fn(o) {
        o.address.payment_credential == Credential.VerificationKey(receiver)
      },
    )
  let total_paid =
    foldl(
      outs,
      0,
      fn(o, acc) {
        acc + assets.quantity_of(o.value, agent_policy_id, agent_asset_name)
      },
    )
  total_paid == expected_amount
}

/// If partner_cut == 0 => skip, else check exact payment to partner
pub fn partner_cut_check(
  outputs: List<Output>,
  partner: VerificationKeyHash,
  agent_policy_id: ByteArray,
  agent_asset_name: ByteArray,
  cut: Int,
) -> Bool {
  if cut == 0 {
    True
  } else {
    verify_exact_payment(
      outputs,
      partner,
      agent_policy_id,
      agent_asset_name,
      cut,
    )
  }
}

/// verify that exactly one NFT is burned (amt == -1) and no other tokens
pub fn verify_nft_burning(mint, nft_policy_id: PolicyId) -> Bool {
  let minted_dict = assets.tokens(mint, nft_policy_id)
  let minted_vals = dict.values(minted_dict)
  when minted_vals is {
    [-1] -> True
    _ -> False
  }
}

/// verify that there's no net mint/burn for the NFT (either no entry or a zero entry)
pub fn verify_no_nft_change(mint, nft_policy_id: PolicyId) -> Bool {
  let minted_dict = assets.tokens(mint, nft_policy_id)
  let vs = dict.values(minted_dict)
  when vs is {
    [] -> True
    [0] -> True
    _ -> False
  }
}

/// Validate basic subscription datum
pub fn validate_subscription_datum(d: SubscriptionDatum) -> Bool {
  and {
    d.partner_percentage >= 0,
    d.partner_percentage <= 100,
    d.subscription_end > d.subscription_start,
  }
}

/// Check if a transaction's validity interval is contained within subscription active range
pub fn check_subscription_active(
  d: SubscriptionDatum,
  tx_range: Interval<Int>,
) -> Bool {
  let s_interval = between(d.subscription_start, d.subscription_end)
  hull(tx_range, s_interval) == s_interval
}

/// The main spending validator
validator subscription_spend(
  agent_policy_id: ByteArray,
  agent_asset_name: ByteArray,
  admin: VerificationKeyHash,
  // The subscription NFT policy ID
  nft_policy_id: PolicyId,
) {
  spend(
    datum_opt: Option<SubscriptionDatum>,
    redeemer: Action,
    input: OutputReference,
    tx: Transaction,
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
    expect Some(Input { output_reference: _, output: old_output }) =
      find_input(inputs, input)
    let script_addr = old_output.address

    // only 1 input from this script => no double satisfaction
    expect ensure_single_script_input(inputs, script_addr)

    when redeemer is {
      //
      // 1) Extend
      //
      Extend { additional_intervals } -> {
        expect check_subscription_active(datum, validity_range)

        // Must have 1 continuing output at script
        let script_outs = filter(outputs, fn(o) { o.address == script_addr })
        expect 1 = length(script_outs)
        expect Some(new_output) = head(script_outs)
        expect InlineDatum(dat) = new_output.datum
        expect new_datum: SubscriptionDatum = dat

        // Only subscriber can do this
        let subSigned =
          foldl(
            extra_signatories,
            False,
            fn(sig, acc) { acc || sig == datum.subscriber_key_hash },
          )
        expect subSigned

        // Basic checks
        expect validate_subscription_datum(new_datum)

        // Must deposit subscription_amount * additional_intervals
        expect additional_intervals > 0

        let old_agent =
          assets.quantity_of(
            old_output.value,
            agent_policy_id,
            agent_asset_name,
          )
        let new_agent =
          assets.quantity_of(
            new_output.value,
            agent_policy_id,
            agent_asset_name,
          )
        let required_diff = subscription_amount * additional_intervals
        expect new_agent == old_agent + required_diff

        // subscription_end advanced
        expect
          new_datum.subscription_end == datum.subscription_end + additional_intervals * datum.interval_length

        // all other fields must remain unchanged
        expect and {
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
            length(new_datum.installments) == length(datum.installments) + additional_intervals,
            // keep NFT
            assets.quantity_of(new_output.value, nft_policy_id, #"") == 1,
            // no net NFT mint/burn for an Extend
            verify_no_nft_change(mint, nft_policy_id) == True,
          }
      }

      //
      // 2) MerchantWithdraw
      //
      MerchantWithdraw -> {
        expect check_subscription_active(datum, validity_range)
        // Must have installments left
        expect datum.installments != []
        expect [due, ..remaining] = datum.installments

        // time check for that installment
        expect contains(validity_range, due.claimable_at)

        let script_outs = filter(outputs, fn(o) { o.address == script_addr })

        when length(remaining) is {
          0 -> {
            // Only merchant can sign
            let merchantSigned =
              foldl(
                extra_signatories,
                False,
                fn(sig, acc) { acc || sig == datum.merchant_key_hash },
              )
            expect merchantSigned

            let total_due = due.claimable_amount
            let partner_cut = total_due * datum.partner_percentage / 100
            let merchant_cut = total_due - partner_cut
            expect partner_cut + merchant_cut == total_due

            expect
              verify_exact_payment(
                outputs,
                datum.merchant_key_hash,
                agent_policy_id,
                agent_asset_name,
                merchant_cut,
              )
            expect
              partner_cut_check(
                outputs,
                datum.partner_key_hash,
                agent_policy_id,
                agent_asset_name,
                partner_cut,
              )

            // must burn NFT => final end
            expect verify_nft_burning(mint, nft_policy_id)
            // no continuing script outputs
            expect is_empty(script_outs)
          }

          _ -> {
            expect 1 = length(script_outs)
            expect Some(new_output) = head(script_outs)
            expect InlineDatum(nd) = new_output.datum
            expect new_datum: SubscriptionDatum = nd

            let merchantSigned =
              foldl(
                extra_signatories,
                False,
                fn(sig, acc) { acc || sig == datum.merchant_key_hash },
              )
            expect merchantSigned

            let total_due = due.claimable_amount
            let partner_cut = total_due * datum.partner_percentage / 100
            let merchant_cut = total_due - partner_cut
            expect partner_cut + merchant_cut == total_due

            expect
              verify_exact_payment(
                outputs,
                datum.merchant_key_hash,
                agent_policy_id,
                agent_asset_name,
                merchant_cut,
              )
            expect
              partner_cut_check(
                outputs,
                datum.partner_key_hash,
                agent_policy_id,
                agent_asset_name,
                partner_cut,
              )

            // keep NFT => no burn
            expect verify_no_nft_change(mint, nft_policy_id)

            expect and {
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
                assets.quantity_of(new_output.value, nft_policy_id, #"") == 1,
              }
          }
        }
      }

      //
      // 3) Unsubscribe
      //
      Unsubscribe -> {
        let now = current_time_for_subscriber(validity_range)
        expect check_subscription_active(datum, validity_range)

        // only subscriber can do it
        let subscriberSigned =
          foldl(
            extra_signatories,
            False,
            fn(sig, acc) { acc || sig == datum.subscriber_key_hash },
          )
        expect subscriberSigned

        let elapsed = now - datum.subscription_start
        let (admin_amount, user_amount) = calculate_penalty(elapsed)

        // must burn NFT
        expect verify_nft_burning(mint, nft_policy_id)

        // find outputs for admin, partner, subscriber
        let admin_out_opt =
          find(
            outputs,
            fn(o) {
              o.address.payment_credential == Credential.VerificationKey(admin)
            },
          )
        let partner_out_opt =
          find(
            outputs,
            fn(o) {
              o.address.payment_credential == Credential.VerificationKey(
                datum.partner_key_hash,
              )
            },
          )
        let user_out_opt =
          find(
            outputs,
            fn(o) {
              o.address.payment_credential == Credential.VerificationKey(
                datum.subscriber_key_hash,
              )
            },
          )

        let partner_cut = admin_amount * datum.partner_percentage / 100
        let final_admin_amount = admin_amount - partner_cut

        let so = filter(outputs, fn(o) { o.address == script_addr })

        when admin_amount is {
          0 -> {
            expect Some(user_out) = user_out_opt
            expect and {
                assets.quantity_of(
                  user_out.value,
                  agent_policy_id,
                  agent_asset_name,
                ) == user_amount,
                is_empty(so),
              }
          }
          _ -> {
            expect Some(ad_out) = admin_out_opt
            expect Some(u_out) = user_out_opt

            let partner_ok =
              if partner_cut == 0 {
                True
              } else {
                expect Some(p_out) = partner_out_opt
                assets.quantity_of(
                  p_out.value,
                  agent_policy_id,
                  agent_asset_name,
                ) == partner_cut
              }

            expect and {
                assets.quantity_of(
                  ad_out.value,
                  agent_policy_id,
                  agent_asset_name,
                ) == final_admin_amount,
                assets.quantity_of(
                  u_out.value,
                  agent_policy_id,
                  agent_asset_name,
                ) == user_amount,
                partner_ok,
                is_empty(so),
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
        let subscriberSigned =
          foldl(
            extra_signatories,
            False,
            fn(sig, acc) { acc || sig == datum.subscriber_key_hash },
          )
        expect subscriberSigned

        // must burn NFT
        expect verify_nft_burning(mint, nft_policy_id)

        let so = filter(outputs, fn(o) { o.address == script_addr })
        expect and {
            verify_exact_payment(
              outputs,
              datum.subscriber_key_hash,
              agent_policy_id,
              agent_asset_name,
              subscription_amount,
            ),
            is_empty(so),
          }
      }
    }

    True
  }

  else(_) {
    fail
  }
}

// Quick test
test subscription_active_test() {
  let test_interval = between(100, 100)
  let d =
    SubscriptionDatum {
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
      partner_percentage: 0,
    }
  check_subscription_active(d, test_interval) == True
}
