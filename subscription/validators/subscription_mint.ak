use aiken/collection/list.{foldl, find}
use aiken/collection/dict
use aiken/crypto.{VerificationKeyHash}
use cardano/transaction.{Transaction, Output, InlineDatum}
use cardano/address.{Credential}
use cardano/assets
use cardano/assets.{PolicyId}
use subscription_spend.{Installment}

/// Data structure (identical to the subscription datum).
/// We'll parse it to ensure the minted UTxO is valid at creation.
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

/// Redeemers for NFT creation or destruction
pub type MintAction {
    Subscribe
    CancelSubscription
}

/// Optional helper to validate that partner_percentage and time range is correct
pub fn validate_initial_datum(d: SubscriptionDatum) -> Bool {
    and {
        d.partner_percentage >= 0,
        d.partner_percentage <= 100,
        d.subscription_end > d.subscription_start
    }
}

/// The advanced minting policy that:
/// 1) Expects a unique `nft_asset_name` param
/// 2) Requires `admin` signature for all mint/burn
/// 3) On Subscribe, also checks the subscriber's signature & 10k TALOS deposit
validator subscription_mint(
    /// Unique name for this NFT
    nft_asset_name: ByteArray,

    /// TALOS token ID (policy & asset name)
    talos_policy_id: ByteArray,
    talos_asset_name: ByteArray,

    /// Admin key for minting
    admin: VerificationKeyHash
) {
    mint(redeemer: MintAction, policy_id: PolicyId, tx: Transaction) {
        let outputs = tx.outputs
        let minted_assets = assets.tokens(tx.mint, policy_id) |> dict.to_pairs()

        // Must be exactly 1 minted/burned asset
        expect length(minted_assets) == 1
        expect [Pair(token_name, amount)] = minted_assets

        // The minted asset name must match the param
        expect token_name == nft_asset_name

        // Admin signature is required
        let admin_signed = foldl(
            tx.extra_signatories,
            False,
            fn(sig, acc) { acc || (sig == admin) }
        )
        expect True = admin_signed

        when redeemer is {
            Subscribe -> {
                // Must be +1 minted
                expect amount == 1

                // Exactly one output with 1 unit of this NFT
                let minted_out_opt = find(outputs, fn(o) {
                    assets.quantity_of(o.value, policy_id, token_name) == 1
                })
                expect Some(minted_out) = minted_out_opt

                // Parse the inline datum
                expect InlineDatum(datum_data) = minted_out.datum
                expect sub_datum: SubscriptionDatum = datum_data

                // Must deposit 10k TALOS in that output
                let talos_locked = assets.quantity_of(
                    minted_out.value,
                    talos_policy_id,
                    talos_asset_name
                )
                expect talos_locked == 10000

                // Validate the initial subscription datum
                expect True = validate_initial_datum(sub_datum)

                // Subscriber must also sign
                let subscriber_signed = foldl(
                    tx.extra_signatories,
                    False,
                    fn(sig, acc) { acc || (sig == sub_datum.subscriber_key_hash) }
                )
                expect True = subscriber_signed
                True
            }

            CancelSubscription -> {
                // Must be -1 burn
                expect amount == -1
                True
            }
        }
    }

    else(_) {
        fail
    }
}
