use aiken/dict
use aiken/list
use aiken/time.{PosixTime}
use aiken/transaction.{Mint, Output, OutputReference}
use aiken/transaction/credential.{VerificationKeyHash}
use aiken/transaction/value

// Type alias for clarity
pub type Time = PosixTime

// Datum for the subscription UTXO
pub type SubscriptionDatum {
  owner: VerificationKeyHash,
  start_time: Time,
}

// Redeemer for minting operations
pub type MintAction {
  Subscribe
  Unsubscribe
}

// Constants for the time periods and penalties
pub const day_in_ms = 86400000 // 24 * 60 * 60 * 1000
pub const penalty_period_1 = 10 * day_in_ms // 10 days in ms
pub const penalty_period_2 = 20 * day_in_ms // 20 days in ms
pub const subscription_period = 30 * day_in_ms // 30 days in ms

// Amount of TALOS tokens for subscription
pub const subscription_amount = 10000 