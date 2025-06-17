use aiken/builtin.{fst_pair, snd_pair}
use aiken/collection/dict
use aiken/collection/list.{find, foldl, length}
use aiken/crypto.{VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Output, Transaction}
use subscription_spend.{Installment}

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

pub type MintAction {
  Subscribe
  CancelSubscription
}

/// Enhanced initial datum validation as per audit recommendations
pub fn validate_initial_datum(d: SubscriptionDatum) -> Bool {
  // Calculate expected number of installments based on subscription period
  let subscription_duration = d.subscription_end - d.subscription_start
  let expected_installments = subscription_duration / d.interval_length
  
  and {
    // Basic validations
    d.partner_percentage >= 0,
    d.partner_percentage <= 100,
    d.subscription_end > d.subscription_start,
    d.interval_length > 0,
    d.service_fee >= 0,
    d.penalty_fee >= 0,
    // Ensure original_subscription_end is set correctly at start
    d.original_subscription_end == d.subscription_end,
    // Verify number of installments matches expected
    length(d.installments) == expected_installments,
    // Ensure subscription duration is a multiple of interval_length
    subscription_duration % d.interval_length == 0,
  }
}

validator subscription_mint(
  nft_asset_name  : ByteArray,
  agent_policy_id : ByteArray,
  agent_asset_name: ByteArray,
  admin           : VerificationKeyHash,
) {
  mint(redeemer: MintAction, policy_id: PolicyId, tx: Transaction) {
    let outputs       = tx.outputs
    let minted_pairs  = assets.tokens(tx.mint, policy_id) |> dict.to_pairs()

    expect [single_pair] = minted_pairs

    let token_name = fst_pair(single_pair)
    let amount     = snd_pair(single_pair)

    expect (trace @"token_name" (token_name == nft_asset_name)?)
    let admin_signed =
      foldl(tx.extra_signatories, False,
        fn(sig, acc) { acc || sig == admin })
    expect (trace @"admin_signed" (admin_signed?))

    when redeemer is {
      Subscribe -> {
        expect (trace @"amount_is_1" (amount == 1)?)

        let minted_out_opt =
          find(outputs,
            fn(o) { assets.quantity_of(o.value, policy_id, token_name) == 1 })
        expect Some(minted_out) = minted_out_opt

        expect InlineDatum(datum_raw) = minted_out.datum
        expect sub_datum: SubscriptionDatum = datum_raw

        let agent_locked =
          assets.quantity_of(
            minted_out.value,
            agent_policy_id,
            agent_asset_name)
        
        // Calculate expected deposit based on number of installments
        let expected_deposit = length(sub_datum.installments) * 10000
        expect (trace @"agent_deposit_correct" (agent_locked == expected_deposit)?)

        expect (trace @"datum_ok" (validate_initial_datum(sub_datum))?)

        let subscriber_signed =
          foldl(tx.extra_signatories, False,
            fn(sig, acc) { acc || sig == sub_datum.subscriber_key_hash })
        expect (trace @"subscriber_signed" (subscriber_signed)?)

        True
      }

      CancelSubscription -> {
        expect (trace @"amount_is_minus1" (amount == -1)?)
        True
      }
    }
  }

  else (_) { fail }
}
