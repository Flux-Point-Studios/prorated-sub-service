use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{ScriptContext, Transaction}
use aiken/transaction/credential.{ScriptCredential, VerificationKey}
use aiken/transaction/value
use subscription/lib/subscription.{
  MintAction, SubscriptionDatum, day_in_ms, penalty_period_1, penalty_period_2,
  subscription_amount, subscription_period,
}

// Spending validator
validator spend(datum: SubscriptionDatum, _redeemer: Data, ctx: ScriptContext) {
  let ScriptContext { transaction, purpose } = ctx
  let Transaction { outputs, mint, extra_signatories, validity_range, .. } = transaction
  
  let admin: ByteArray = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  let talos_policy_id: ByteArray = #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd" 
  let talos_asset_name: ByteArray = #"74616c6f73"

  // 1. Verify the owner's signature
  expect list.any(extra_signatories, fn(sig) { sig == datum.owner })

  // 2. Calculate elapsed time and determine penalty
  let current_time = 
    when validity_range.lower_bound.bound_type is {
      Finite(time) -> time
      _ -> error(@"Invalid validity interval lower bound")
    }
  
  let elapsed = current_time - datum.start_time
  
  // Calculate penalty percentage and return amounts
  let (admin_amount, user_amount) =
    if elapsed < penalty_period_1 {
      // Less than 10 days: 30% penalty
      (subscription_amount * 30 / 100, subscription_amount * 70 / 100)
    } else if elapsed < penalty_period_2 {
      // 10-20 days: 20% penalty
      (subscription_amount * 20 / 100, subscription_amount * 80 / 100)
    } else if elapsed < subscription_period {
      // 20-30 days: 10% penalty
      (subscription_amount * 10 / 100, subscription_amount * 90 / 100)
    } else {
      // 30+ days: 0% penalty
      (0, subscription_amount)
    }

  // 3. Verify the NFT is being burned
  expect list.has_length(value.tokens(mint, #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef"), 1)
  
  expect [token_name, amount] = 
    value.tokens(mint, #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef") |> dict.to_list()
      
  expect amount == -1
  
  // 4. Verify the penalty distribution
  let admin_output_opt = 
    list.find(outputs, fn(output) {
      output.address.payment_credential == VerificationKey(admin) 
    })
    
  let user_output_opt =
    list.find(outputs, fn(output) {
      output.address.payment_credential == VerificationKey(datum.owner)
    })
  
  // Admin output might not exist if penalty is 0
  when admin_amount is {
    0 -> 
      expect Some(user_output) = user_output_opt
      value.quantity_of(user_output.value, talos_policy_id, talos_asset_name) == user_amount
    _ -> 
      expect Some(admin_output) = admin_output_opt
      expect Some(user_output) = user_output_opt
      value.quantity_of(admin_output.value, talos_policy_id, talos_asset_name) == admin_amount &&
      value.quantity_of(user_output.value, talos_policy_id, talos_asset_name) == user_amount
  }
}

// Minting policy
validator mint(redeemer: MintAction, ctx: ScriptContext) {
  let ScriptContext { transaction, purpose } = ctx
  let Transaction { outputs, mint, .. } = transaction
  
  let talos_policy_id: ByteArray = #"aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccdd" 
  let talos_asset_name: ByteArray = #"74616c6f73"
  
  let minted_assets = value.tokens(mint, #"abcdef1234567890abcdef1234567890abcdef1234567890abcdef") |> dict.to_list()
  
  expect list.has_length(minted_assets, 1)
  expect [(token_name, amount)] = minted_assets
  
  when redeemer is {
    MintAction.Subscribe -> {
      // Must be minting exactly one NFT
      expect amount == 1
      
      // Validate there's an output locking 10000 TALOS at this script
      list.any(outputs, fn(output) {
        value.quantity_of(output.value, talos_policy_id, talos_asset_name) == subscription_amount
      })
    }
    
    MintAction.Unsubscribe -> {
      // Must be burning exactly one NFT
      expect amount == -1
      
      // The spend validator ensures the subscription is being withdrawn correctly
      True
    }
  }
}

// Helper function to get policy ID from mint purpose
fn policy_id_from_mint_purpose(ctx: ScriptContext) -> ByteArray {
  when ctx.purpose is {
    transaction.Mint(policy_id) -> policy_id
    _ -> error(@"Not in minting context")
  }
}

// Helper function to get script credential from spend purpose
fn script_credential_from_spend_purpose(ctx: ScriptContext) -> transaction.credential.Credential {
  when ctx.purpose is {
    transaction.Spend(output_ref) -> ScriptCredential(output_ref.transaction_id)
    _ -> error(@"Not in spending context")
  }
}

// Helper to check if an output contains the expected amount of tokens
fn check_output_amount(
  output: transaction.Output,
  policy_id: ByteArray,
  asset_name: ByteArray,
  expected_amount: Int,
) -> Bool {
  value.quantity_of(output.value, policy_id, asset_name) == expected_amount
} 