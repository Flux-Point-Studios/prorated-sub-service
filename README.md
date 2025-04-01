# prorated-sub-service


## Overview of the Subscription System

We propose a **Cardano smart contract-based subscription system** for the **$TALOS** token with a 30-day access period per subscription. The system uses **Aiken** (a high-level language for Cardano’s Plutus V3) to implement the on-chain logic. The core idea is that users **lock 10,000 $TALOS tokens** into a smart contract to activate a 30-day subscription, and in return receive a **non-fungible token (NFT)** as an on-chain certificate of their subscription. The NFT represents the active subscription and is recorded on-chain. Key features of the design include:

- **Token Locking**: Users initiate a subscription by sending **10,000 $TALOS** (exact amount) to the contract address. This locks the tokens on-chain for a period of up to 30 days.
- **Subscription NFT**: In the same transaction as the deposit, the contract mints a unique **subscription NFT** to the user’s wallet. This NFT serves as proof of subscription on-chain ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=In%20the%20context%20of%20this,NFT%20as%20a%20gift%20card)). It can be used off-chain to verify access rights (e.g. the user can present the NFT to a service as proof of subscription).
- **Time-Limited Access**: The subscription duration is 30 days. After 30 days, the user is entitled to withdraw their locked tokens **without penalty** (and the subscription is considered expired). 
- **Early Withdrawal & Penalties**: Users can **cancel (withdraw) early**, but graded **penalty fees** apply based on how early they withdraw:
  - Withdraw in first 10 days: **30% penalty** (user gets back 70% of locked tokens)
  - Withdraw day 10–20: **20% penalty** (user gets back 80%)
  - Withdraw day 20–30: **10% penalty** (user gets back 90%)
  - After 30 days: **0% penalty** (full 100% return)
- **Penalty Distribution**: Penalty amounts are not burned – they are sent to an **admin/treasury wallet** as a fee. An **admin address** is designated in the contract to collect these penalty fees.
- **On-Chain Tracking & Off-Chain Verification**: The presence of the NFT in a user’s wallet (and/or the existence of their locked UTXO on-chain) is an on-chain record of an active subscription. As a fallback, if the contract is unreachable or fails, the system can verify a user’s subscription status off-chain by checking the user’s wallet address for the subscription NFT or the locked funds.
- **Security**: Only the **original depositor** (subscription owner) can withdraw their tokens (enforced by their signature on the transaction). The contract logic ensures correct penalty is paid and the subscription NFT is **burned** upon early withdrawal to prevent reuse. We assume production-grade security, using Cardano’s **Extended UTXO model** and Plutus V3 features (e.g. time checks via transaction validity intervals, reference scripts, etc.) to prevent double-spends or abuse.

In summary, the flow is: **(1)** User locks 10,000 TALOS in the contract and receives an NFT certificate. **(2)** User enjoys 30 days of access (off-chain services can check NFT ownership to grant access). **(3)** If the user withdraws early, part of the tokens are taken as a fee (to admin) and the NFT is invalidated. **(4)** If the user waits 30+ days, they withdraw all tokens (NFT expires or is burned on withdrawal). The sections below detail the on-chain contract logic, data structures, and the implementation plan using Aiken.

## Smart Contract Architecture (Aiken & Plutus V3)

The subscription system is implemented as an **Aiken validator script** with two roles: a **spending validator** (for handling withdrawals of locked TALOS) and a **minting policy** (for issuing and burning the subscription NFTs). Aiken allows us to define both spending and minting logic in one validator, using Plutus V3 capabilities. This single smart contract will govern the entire lifecycle of a subscription. We outline the contract components and logic:

### On-Chain Components

- **Validator Script Address**: A Plutus script address (derived from the validator’s hash) where users send the 10,000 TALOS to lock them. Each subscription lock becomes a UTXO at this script address.
- **Datum**: Attached to each UTXO at the script, encoding the state of that subscription (e.g. the owner’s key and timestamps). We use an **inline datum** (enabled by Plutus V2+) to store this data on-chain with the UTXO.
- **Redeemer**: Used when spending (withdrawing) from the script. We define a custom redeemer type to distinguish actions if needed (though in this design a simple unit or a flag can suffice since conditions are inferred from context and time).
- **Subscription NFT**: A native asset minted by the contract to represent the subscription. It has a unique **policy ID** (the hash of the contract’s minting policy) and a unique **token name** per subscription. This NFT is sent to the user’s wallet on subscription start, and must be burned (minted with a negative quantity) when the user withdraws their deposit (ending the subscription). 
- **TALOS Token**: The contract will specifically handle the TALOS native token. We assume the **policy ID of TALOS** is known and fixed (to identify TALOS in the script logic), and that 10,000 is the exact integer amount for one subscription. (For example, if TALOS has decimals, 10,000 represents that many base units accordingly.)
- **Admin Public Key**: The public key hash (or address) of the admin/treasury wallet is hard-coded or parameterized in the validator. This is used to ensure penalty fees are paid to the correct address on early withdrawals.

### Datum Design and Token Locking

Each subscription UTXO will carry a **datum** recording necessary information for validation. We define the datum as a structure with at least the following fields:

- `owner : VerificationKeyHash` – The hashed public key of the user who locked the tokens. This ties the UTXO to the owner’s wallet. Only this key will be authorized to withdraw the tokens.
- `start_time : Time` – The start time of the subscription (could be a POSIX timestamp or slot number when the deposit occurred). From this we can derive the subscription end time (start_time + 30 days) and calculate how much time has elapsed at withdrawal.
- Alternatively, we could store `expiry_time : Time` (the timestamp when 30 days will have passed) instead of start_time. Either approach allows computing remaining time. In this design we’ll use `start_time` for illustration.
- (Optionally) `duration : Int` – could store the constant 30-day duration or not needed if assumed.
- (Optionally) `token_name : ByteArray` – if we want to record the exact token name of the NFT associated (though the NFT policy logic can derive or verify it independently).

When a user subscribes, the off-chain code will create a transaction that **locks 10,000 TALOS** at the script address with an inline datum containing the `owner` (user’s key) and `start_time` (current time). The contract will enforce that exactly 10,000 TALOS are included. This locking does not consume any existing script UTXO (it’s a fresh output), so the **spending part of the script is not invoked on deposit**. Instead, the **minting policy** part of the script is used to mint the NFT in the same transaction.

**Token Locking Validation**: The contract’s minting policy will verify that the deposit transaction indeed locks the correct amount of TALOS. We ensure that in the transaction outputs there is **exactly one output** at the script address with **10,000 TALOS**. This can be done by inspecting the transaction in the minting policy context. For example, in Aiken pseudocode for the mint (CheckMint branch):

```rust
validator subscription(admin_key: VerificationKeyHash, talosPolicy: PolicyId, talosToken: AssetName) {
    // ... spend handler omitted for now ...

    mint(redeemer: MintAction, policy_id: PolicyId, tx: Transaction) -> Bool {
       // Extract minted assets under this policy
       let minted_assets = assets.tokens(policy_id, tx.mint) 
                       |> dict.to_pairs();
       expect [Pair(subNFT_name, subNFT_amount)] = minted_assets; 
       // Only one asset minted under this policy
       when redeemer is MintAction::Subscribe -> {
            // Must be minting exactly one NFT
            subNFT_amount == 1 &&             // NFT quantity
            // Validate there's an output locking 10000 TALOS at this script
            list.any(tx.outputs, fn(out) {
                out.address.payment_credential == Script(policy_id) &&    // output addressed to this script
                assets.value_of(out.value, talosPolicy, talosToken) == 10000
            }) &&
            // (Optionally) ensure uniqueness of NFT name (discussed below)
            True
       }
       // ... Burn action handled in another branch ...
    }
}
```

In the above pseudo-code, `Script(policy_id)` represents the script address credential matching this validator (Aiken’s `payment_credential` will equal the script’s hash for outputs to the script) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20Some%28own_input%29%20%3D%20list,output_reference%20%3D%3D%20own_ref)). We check that some output in the transaction has 10,000 of the TALOS token (`talosPolicy/talosToken` identifies TALOS) locked at this script address. This guarantees that an NFT cannot be minted unless the required TALOS are actually locked in the same transaction.

**Unique NFT Token Name**: We also want each subscription NFT to be unique so that two NFTs are not interchangeable or duplicative. We can achieve uniqueness by incorporating a unique element (like the transaction or UTXO identifier or the user’s key) into the NFT’s asset name. For example, the asset name could be a hash of the owner’s key and the start time, or even the UTXO itself. A simple scheme: use the depositor’s public key hash (or a part of it) as the NFT name. That way, each user’s subscription NFT is distinct. If the same user tries to subscribe again concurrently, there is a potential name collision – to avoid that, a timestamp or nonce can be appended to the name. In practice, the off-chain code can generate a random or time-based suffix for the NFT name when building the mint, ensuring uniqueness. The minting policy can be slightly flexible to allow any asset name (or enforce a prefix like `"TALOSSub"`). 

For stricter on-chain uniqueness, one pattern is to use a one-shot minting approach: tie the NFT mint to a specific UTXO so it can only happen once ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=At%20this%20point%20we%20have,from%20the%20parameters)). For instance, the contract could require a specific input (like the user’s funding input) to have a reference in the minting policy (as seen in oneshot NFT contracts ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20True%20%3D%20list,output_reference%20%3D%3D%20utxo_ref))). However, since we enforce the presence of a new output with 10,000 TALOS, any attempt to mint another NFT must also lock another 10,000 TALOS. We also restrict that only one NFT can be minted per transaction (`expect [Pair(..)]` ensures a single token minted). This suffices to prevent duplicate free NFTs. (In production, we would carefully consider NFT naming or an on-chain registry UTXO to absolutely guarantee no duplicate subscription NFTs are in circulation, but for this design we assume each deposit TX mints a unique NFT and the NFT must be burned to end that subscription.)

### NFT Minting and Subscription Activation

Upon a successful deposit transaction, the contract mints the **subscription NFT** to the user. The NFT’s policy ID is derived from the validator script, and its token name as discussed is unique per subscription. The NFT is delivered to the user’s wallet address in an output of the same transaction. The NFT signals an active subscription on-chain. Off-chain services can check for the presence of this NFT in the user’s wallet to grant them subscriber-only access.

**On-Chain NFT Policy Logic**: In the Aiken validator’s `mint` handler (as sketched above), the branch for the “Subscribe” action (minting the NFT) enforces the conditions:
- The transaction mints exactly **one** NFT (amount = 1) with the expected policy (it uses the script’s own policy ID).
- The NFT asset name can be checked or constrained if needed (e.g., ensure it has the proper prefix or matches a hash of the owner’s key in the datum).
- The transaction **must include the locking output of 10,000 TALOS** to this script (as described).
- Optionally, we ensure that the input conditions for uniqueness are met (for example, we could require the user’s input UTXO that provides the TALOS is used as a “nonce”, meaning the contract could take a parameter of a specific input reference that must appear in the transaction, as in the “gift card” one-shot NFT example ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=At%20this%20point%20we%20have,from%20the%20parameters)). This prevents reusing the same input to mint another NFT). However, this level of parameterization may require generating a new script instance for each deposit. In our plan, we rely on unique token names and the fact that each NFT requires locking new tokens to avoid duplicates.

Once these conditions are satisfied, the minting policy allows the NFT to be minted. This is **atomic** with the deposit – if any condition is not met, the entire transaction fails. So the user either locks their tokens and gets an NFT, or nothing happens. This atomic behavior is crucial: the NFT is only issued *upon successful locking* of funds (and vice versa). This pattern is identical to a gift card mechanism where locking assets mints a token that can later unlock those assets ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=In%20the%20context%20of%20this,NFT%20as%20a%20gift%20card)).

After this deposit transaction, the on-chain state is:
- A UTXO at the script address containing `10,000 TALOS` (and some ADA for min UTXO) with a datum recording the owner and start time.
- The user’s wallet holds a newly minted **subscription NFT** (with, say, policy ID `PID_sub` and name `Subscription_<user-or-txID>`).
- The NFT can have metadata (optionally attached during mint) indicating details like start date or expiration date for off-chain convenience. (Metadata is not enforced by the chain but can be useful for frontends; e.g., an off-chain metadata server could record that this NFT expires on a certain date.)

### Withdrawal Logic (Spending Validator)

Withdrawals are handled by the **spend validator** part of the contract. When the user’s 30-day period is over (or earlier, if they choose to cancel), they will create a transaction to spend the locked UTXO and return the TALOS to themselves, paying any applicable penalty to the admin. The validator will ensure only the rightful owner can do this, and that the correct penalty rules are applied. Importantly, if the user is ending their subscription (at any time), the subscription NFT **must be burned** in the same transaction, effectively canceling the on-chain subscription record.

**Authorized Withdrawals (Owner check)**: The script must ensure that only the original depositor (owner) can withdraw their tokens. We have the owner’s public key hash in the datum. We enforce that the spending transaction is **signed by the owner’s key**. In Plutus, this is done by checking that the `tx.signatories` (extra signers) includes the owner’s hash. In Aiken, for example, we could use `key_signed(tx.extra_signatories, datum.owner)` ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=key_signed%28tx.extra_signatories%2C%20datum.owner%29%2C%20and%20,)). This prevents anyone else (except possibly the admin, but we are not giving admin arbitrary spending power in this design) from stealing someone’s locked tokens. 

**NFT Burn requirement**: The spending transaction must include the **burn (mint = -1) of the subscription NFT** associated with this UTXO. We tie the NFT to the UTXO via the contract’s logic. In our unified script design, the same validator that minted the NFT also controls its burning. We will have a second branch in the `mint` handler for a “Unsubscribe” or burn action. The validator will check that exactly one NFT of the correct policy and name is being burned (minted with amount = -1) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=CheckBurn%20)). Moreover, the validator’s spend logic can ensure that the NFT burn corresponds to the UTXO being spent. In the gift card example, the spend logic explicitly checked that the transaction’s minted assets include the negative NFT and that the script input being spent matches the one tied to that NFT ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20Some%28own_input%29%20%3D%20list,output_reference%20%3D%3D%20own_ref)) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=amount%20%3D%3D%20,token_name)). We will do similarly: the spend logic will look at `tx.mint` and expect to find the `-1` amount for the NFT of the given policy and token name. If the NFT is not burned, the validation fails. This guarantees that when tokens are withdrawn (subscription ended), the NFT is canceled, preventing the user from retaining a subscription NFT without locking tokens.

**Time-Based Penalty Calculation**: The crux of the withdrawal logic is enforcing the **penalty tiers** based on how much time has passed since `start_time`. The contract uses the current **block time** (from the transaction’s validity interval) to determine the category:
- If the user withdraws very early (<10 days since start), 30% penalty.
- If 10–20 days, 20% penalty.
- If 20–30 days, 10% penalty.
- If >=30 days, no penalty.

**Using Transaction Time**: Plutus smart contracts determine the “current” time via the transaction’s **validity interval**. The off-chain code will set the `validity_range` of the withdrawal transaction to specify a time window in which the transaction is valid. For example, it may set the lower bound (`valid_from`) to the current slot/time and no upper bound beyond some limit. The script can then use functions like `valid_after` or check the interval against the datum’s times. In Aiken, a helper like `valid_after(tx.validity_range, datum.lock_until)` returns true if the transaction’s validity start is after the stored time ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=and%20,)). We will invert that logic to check if the transaction is *before* certain times for penalty conditions. Alternatively, the off-chain code can explicitly constrain the transaction with an upper bound to signal the intended penalty bracket. For instance, for a 30% penalty withdrawal, the wallet might set the transaction’s upper time bound to `start_time + 10 days` to indicate it’s taking place before the 10-day mark.

Inside the validator, we can compute or check the elapsed time. One approach:
- Compute `elapsed = current_time - datum.start_time`. (While we can’t directly subtract times in Plutus easily without conversion, we can use comparisons against constants.)
- Use conditional checks: 
  - If `elapsed < 10 days` (i.e. current time is earlier than start_time + 10 days) then enforce 30% penalty.
  - Else if `elapsed < 20 days` then enforce 20% penalty.
  - Else if `elapsed < 30 days` then enforce 10% penalty.
  - Else (>= 30 days) enforce 0% penalty.

In Plutus, direct arithmetic on time might be tricky, so more practically we use the transaction’s validity interval bounds:
  - For 30% penalty case: ensure the transaction’s **upper bound** is `<= start_time + 10d`. This implies the transaction is not valid after the 10-day point, effectively meaning it must execute before or at that threshold.
  - For 20% penalty: ensure `start_time + 10d <= tx.valid_from < start_time + 20d` (or similarly use upper bound <=20d and maybe >=10d).
  - For 10%: ensure `tx.valid_from` >= 20d and < 30d.
  - For no penalty: require `valid_from >= start_time + 30d` (i.e. `valid_after(tx.validity_range, start_time + 30d)` is true, meaning current time is after the lock period).

For simplicity, we can implement these as conditional branches in Aiken. Pseudocode within the validator’s `spend` handler might look like:

```rust
spend(datum: SubscriptionDatum, _redeemer: Data, context: Transaction) -> Bool {
    // Require owner's signature
    enforce key_signed(context.extra_signatories, datum.owner);

    // Determine current time from validity range
    let validRange = context.validity_range;
    // We'll use helper functions or comparisons for time:
    // (Assume datum.start_time and constants are in milliseconds or slot units as appropriate)
    // Define thresholds:
    let t10 = datum.start_time + 10_days;
    let t20 = datum.start_time + 20_days;
    let t30 = datum.start_time + 30_days;

    // Penalty conditions:
    if context.validity_range.last <= t10 {
        // Before 10 days
        checkPenaltyDistribution(percent = 30);
    } else if context.validity_range.last <= t20 {
        // Before 20 days (but after 10 days)
        enforce context.validity_range.first >= t10;  // ensure at or after 10-day mark
        checkPenaltyDistribution(percent = 20);
    } else if context.validity_range.last <= t30 {
        // Before 30 days (after 20 days)
        enforce context.validity_range.first >= t20;
        checkPenaltyDistribution(percent = 10);
    } else {
        // 30 days or later
        enforce context.validity_range.first >= t30;
        checkPenaltyDistribution(percent = 0);
    }

    // Also require that one subscription NFT is burned in this tx:
    let burned_assets = assets.tokens(THIS_POLICY_ID, context.mint) |> dict.to_pairs();
    expect [Pair(subNFT_name, subNFT_amount)] = burned_assets;
    enforce subNFT_amount == -1;
    // (Optionally check subNFT_name matches the expected name from datum or a hash of owner)

    return True;
}
```

*(Note: The above is pseudocode for illustration. In Aiken, one would use pattern matching and library calls like `valid_before`/`valid_after` to neatly express time conditions. The concept is that the **transaction’s time validity must align with the intended penalty bracket**, and the contract verifies that, then applies the corresponding distribution check.)*

The helper `checkPenaltyDistribution(percent)` would enforce that the outputs of the transaction are split such that the **admin** receives `percent%` of the 10,000 TALOS and the **user** receives the rest. Since 10,000 TALOS is the deposit, the amounts are fixed for each case:
- 30% penalty -> admin gets 3,000 TALOS, user gets 7,000 TALOS.
- 20% -> admin 2,000, user 8,000.
- 10% -> admin 1,000, user 9,000.
- 0% -> admin 0, user 10,000.

**Output Distribution Checks**: We find the outputs in the transaction that correspond to the admin and the user:
- The **admin output**: must be an output whose address matches the admin wallet and contains the penalty amount of TALOS.
- The **user output**: should go back to the user (owner). Likely it will be to the owner’s own public key address. We can enforce that the payment credential of that output’s address equals the owner’s key hash from the datum, and it contains the correct amount of TALOS.

Additionally, we enforce that the **total** TALOS in those two outputs equals 10,000 (no tokens lost or magically created). The contract should also ensure no TALOS are going anywhere else. In practice, if our checks specifically pick out the user and admin outputs by credentials and check their values, that implicitly ensures no other output carries TALOS because the total minted/burned TALOS in the transaction is zero (TALOS is not being minted or burned, just moved) and if some third output had TALOS, then the sum to user+admin would be less than 10,000. We can explicitly check sum equality for safety.

For example, in Aiken style:

```rust
fn checkPenaltyDistribution(datum: SubscriptionDatum, tx: Transaction, percent: Int) -> Bool {
    let penaltyTokens = 10000 * percent / 100;
    let userTokens    = 10000 - penaltyTokens;
    // Find admin output
    let admin_out_opt = list.find(tx.outputs, fn(out) {
         out.address.payment_credential == Key(admin_key_hash)
    });
    // Find user output
    let user_out_opt = list.find(tx.outputs, fn(out) {
         out.address.payment_credential == Key(datum.owner)
    });
    expect Some(admin_out) = admin_out_opt;
    expect Some(user_out)  = user_out_opt;
    // Check TALOS amounts in outputs:
    enforce assets.value_of(admin_out.value, talosPolicy, talosToken) == penaltyTokens;
    enforce assets.value_of(user_out.value, talosPolicy, talosToken) == userTokens;
    // Ensure the sum matches exactly 10000 (could sum and compare, or rely on no other outputs carrying TALOS)
    enforce assets.value_of(admin_out.value + user_out.value, talosPolicy, talosToken) == 10000;
    True
}
```

The above logic will fail if, for example, the user tries to keep more tokens than allowed or pays less fee. It will also fail if the timing doesn’t match the claimed penalty bracket. For instance, if a user tries to withdraw on day 5 but only pay a 20% penalty (which is meant for 10+ days), the transaction’s validity might be set beyond 10 days or the contract will detect that the interval doesn’t satisfy the `< 10 days` condition for 30% (the first branch) and move to the second branch expecting a 20% penalty, but then `context.validity_range.first` won’t be >=10 days (since it’s day 5). Thus the checks won’t line up and the transaction is invalid. Conversely, if the user tries to lie about time, the block timestamp won’t cooperate. This ensures honest execution of the penalty rules.

**No-Penalty Withdrawal**: After 30 days, the `percent = 0` branch expects the user to get all 10,000 TALOS and the admin to get 0. In this case, we may not even require an admin output at all. Our check can allow that the admin output is optional when penaltyTokens = 0 (or we find none and that’s fine). We will enforce that if no admin output is found, then `percent` must be 0. Alternatively, we could require an output to admin of 0 TALOS (but that would just be dust and unnecessary). So for the 0% case, we adapt the logic to not expect an admin output; we simply ensure the user’s output carries 10,000 TALOS.

**Completing the Spend Validation**: Along with the above conditions, we finalize by ensuring the NFT burn is present as discussed. In Aiken, since our validator has both spend and mint capabilities, we can directly access the `tx.mint` inside the spend logic. In the gift card reference, they do this by finding the script input (`own_input`) and extracting its address’s script hash to get the policy ID, then matching the minted asset under that policy ID ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20Some%28own_input%29%20%3D%20list,output_reference%20%3D%3D%20own_ref)). In our case, `policy_id` for the NFT is known (it’s the same as the validator’s hash or provided as `THIS_POLICY_ID` in the context). So we can simply filter `tx.mint` for our policy and ensure one asset with amount -1 exists. For example, the spend part in Aiken might look like:

```rust
spend(datum: SubscriptionDatum, _redeemer: Data, _own_ref: OutputReference, tx: Transaction) -> Bool {
    // Owner signature check
    expect True = key_signed(tx.extra_signatories, datum.owner);

    // Determine which penalty branch applies using tx.validity_range and datum.start_time
    ... (time logic and call checkPenaltyDistribution as above) ...

    // Check NFT burn in the same transaction
    let policyId = SCRIPT_POLICY_ID;  // the policy ID of this script/NFT
    expect [Pair(asset_name, amount)] = tx.mint 
                                         |> assets.tokens(policyId) 
                                         |> dict.to_pairs();
    enforce amount == -1 && asset_name == expectedName(datum);  // expectedName(datum) yields the NFT name we expect, possibly derived from owner or start_time
    True
}
```

Here we used a hypothetical `SCRIPT_POLICY_ID` which would be the hash of the minting policy (in Aiken, `policy_id` is passed into the mint function, but in the spend we derived it in gift card by looking at our own script input’s address which contains the script hash ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20Some%28own_input%29%20%3D%20list,output_reference%20%3D%3D%20own_ref))). Since the spend is occurring at this script, one of the transaction inputs is the UTXO being spent; we can get its address credential to get the script hash (which equals our validator hash). This is what the gift card example did with `own_input.output.address.payment_credential == Script(policy_id)` and then using that `policy_id` ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=list.find%28inputs%2C%20fn%28input%29%20,own_ref)). We would replicate that pattern to obtain the policy id inside the spend logic, if not already known.

The condition `asset_name == expectedName(datum)` is to double-check the correct NFT is being burned. If we stored the asset name or could derive it (say the NFT name was based on owner key), we can ensure it matches. This prevents someone from burning a different NFT they hold to satisfy the burn requirement erroneously.

### Admin Fee Collection and Role

The **admin wallet** (or treasury) is simply a Cardano address (likely a public key address controlled by the project team) configured in the contract. Its role is passive in that it just receives the penalty fees. The contract ensures that on any early withdrawal, the admin’s address appears as an output with the correct fee amount. The admin does not need to sign or trigger these transactions; the user’s withdrawal transaction will include the output to admin as a requirement of validation.

Once the penalty tokens are in the admin’s address, the admin can freely spend them (it’s just a normal UTXO in their wallet). We might, for accounting, label these outputs or use a specific address for subscription fees. The admin can **collect fees** by periodically consolidating those UTXOs if needed. The contract does **not** hold the fees; they are delivered directly to the admin wallet in the same transaction. Thus, the admin does not need a separate action to withdraw penalties from the script – it happens automatically at user withdrawal time.

**Admin as Fallback**: Our design does not give the admin the ability to arbitrarily take a user’s deposit. Only the user (with their signature and NFT) can unlock their funds. This is a security choice to protect users. If a user’s 30 days pass and they do nothing, their funds remain locked in the script (and the NFT in their wallet remains valid but effectively expired for access after 30 days). The admin cannot take those tokens unless a clause was added to allow, say, seizure after some long period. We do not include such a clause here to keep trust minimized; however, this means **users must withdraw their deposit manually** when their subscription ends or if they want to cancel. (In an extension, one could allow the admin to reclaim long-dormant deposits after a grace period – that would involve an additional branch in the validator allowing admin signature after, say, 60 days, to prevent UTXOs from staying forever. This is a design choice depending on requirements.)

### Off-Chain Client Interactions

To use this system, we need off-chain code (a dApp backend, CLI scripts, or wallet integration) to construct and submit transactions for both subscription activation and termination. We outline how the client should handle each:

**1. Subscribing (Locking and Minting)**:
   - The client (user’s wallet or dApp) prepares a transaction where:
     - **Input**: The user provides at least 10,000 TALOS (plus enough ADA for fees and min UTXOs) from their wallet UTXOs.
     - **Outputs**:
       - One output to the **subscription script address** with:
         - Value: 10,000 TALOS + min ADA.
         - Inline Datum: `SubscriptionDatum { owner = userPubKeyHash, start_time = currentTime, ... }`.
       - One output to the **user’s own address** containing the **minted subscription NFT** (with some ADA to satisfy min UTXO).
       - (Optional) A change output back to user for any leftover ADA/TALOS not locked.
     - **Mint**: The transaction must include a minting entry for the subscription NFT: Policy = subscription script’s policy, Asset = NFT token name, Amount = 1. The **redeemer** for the mint action would indicate the “Subscribe” action (in Aiken we used an enum like `MintAction::Subscribe`). This informs the on-chain validator to run the CheckMint branch.
     - **Fee**: Include ADA to pay transaction fees.
     - **Signatures**: The user signs the transaction (since they are spending their own UTXOs to fund the lock and paying fees). No special script signature is required for minting; the policy logic will validate internally.
     - **Submit**: The transaction is submitted to the blockchain.

   If constructed correctly, the contract’s minting policy approves the mint (and thereby the lock). On-chain, this results in the locked UTXO and NFT as described. The off-chain client should then confirm the transaction succeeded and possibly record the details (e.g., store the UTXO ID and NFT info if needed for UI).

   *Note:* Because the datum contains `start_time`, the client should set this to the current time. Typically, one might use the current slot or block time. The transaction can also set its `validity_range` so that it’s only valid for a short window around the intended time (to avoid the transaction being added much later than the timestamp in datum). In practice, slight discrepancies of a few seconds or minutes in `start_time` won’t matter much for a 30-day period. It’s mainly used for on-chain logic, and we consider the block time as authoritative for withdrawal timing.

**2. Checking Subscription Status (Off-chain)**:
   - A user or service can check if a given wallet has an **active subscription** in a couple of ways:
     - **Check for the Subscription NFT in the user’s wallet**. If the NFT is present and not burnt, it indicates the user has an ongoing subscription. One should also verify that the NFT’s corresponding deposit hasn’t been withdrawn. This can be done by checking if the script UTXO corresponding to that NFT is still unspent. In many cases, the existence of the NFT is enough, since if they withdrew, the NFT would have been burned and thus removed from circulation.
     - **Check the script UTXO** on-chain. Because each subscription lock is an UTXO at the script with a datum, one could query the blockchain (using a Cardano node or Blockfrost API, etc.) for UTXOs at the subscription script address that have `owner = user`. If such a UTXO exists and its datum’s start_time plus 30 days is in the future (or has not passed yet), then the subscription is active. If the 30 days have passed but the UTXO is still there (user hasn’t withdrawn), the user technically isn’t paying anymore (time expired), so one might consider that subscription expired in terms of service (the NFT still exists but should be considered invalid for access after day 30). In our system, we don’t enforce expiration by auto-burning; it’s up to off-chain logic to treat NFTs older than 30 days as expired. The **NFT metadata** or the datum can provide the expiry to off-chain systems. For example, if the NFT metadata contains an expiry timestamp, a service can simply check that and current time.
   - **Off-chain fallback verification**: If the contract were to fail or be unavailable (say the script had a bug and no one can currently withdraw on-chain), the admins could still verify a user’s subscription by checking these on-chain indicators (NFT and locked UTXO). For instance, an admin could ask the user to sign a message with the wallet that holds the NFT to prove ownership, then manually grant access. In a worst-case scenario, if funds are stuck due to a bug, the admin could even create a custom transaction (if possible) or decide off-chain to compensate the user. These are emergency processes; the on-chain design aims to avoid such failures by thorough testing.

**3. Withdrawing (Redeeming the Subscription)**:
   - When a user decides to withdraw their locked TALOS (cancelling the subscription), they must craft a transaction to spend the script UTXO. This is typically facilitated by a dApp interface or manual via cardano-cli with the correct parameters:
     - **Input**: The UTXO at the subscription script address containing the user’s 10,000 TALOS (the UTXO from the deposit). The input must include the **inline datum** and the **validator script** as a witness (or use a reference script, discussed later).
     - **Outputs**:
       - One output to the **user’s address** with their returned TALOS (minus penalty). For example, if withdrawing on day 5, this output will have 7,000 TALOS; if on day 25, it will have 9,000; if after 30 days, 10,000.
       - One output to the **admin’s address** with the penalty amount (if any). E.g., 3,000 TALOS for day 5 withdrawal; 1,000 TALOS for day 25; none for after 30 days.
       - It’s possible that the user takes their returned TALOS and any leftover ADA in a single output (the change output to themselves serves both purposes) as long as it has the correct amount. Meanwhile the admin output will carry the penalty tokens with some ADA.
     - **Mint**: The transaction includes a **mint entry to burn the NFT**. This will be the same policy as before, asset name equal to the subscription NFT, amount = **-1**. The redeemer for the mint can indicate “Unsubscribe” action. The NFT itself must be present as an input or in the witness set to burn it; practically, the user will have the NFT in their wallet, so they need to include it as an **input (the NFT UTXO)** in the transaction. This means the user must actually *spend the UTXO containing the NFT from their wallet* in the transaction, so that the NFT is in the inputs and can be burned. (If the NFT UTXO also had ADA, the ADA can go to user’s change output.)
     - **Validity Interval**: The wallet sets the time constraints. For example, if current time is day 5, to satisfy the contract it should ensure the transaction does not claim to be past day 10. The easiest way is to set the **upper bound** of the validity interval to `start_time + 10 days` (or a little less, to be safe). This ensures `current_time < 10d` condition holds in script. Similarly, if withdrawing after 20 days but before 30, set upper bound <= `start+30d` and lower bound >= `start+20d` to clearly indicate 10% bracket. If withdrawing after expiry (no penalty), simply set lower bound >= `start+30d`. Many of these can be handled by just ensuring `valid_from` is the current slot (which obviously is > start+20 if 25 days passed) and maybe not setting an upper bound too far.
     - **Signatures**: The user must sign this transaction (because they are spending their script UTXO requires their signature per our validator, and also spending the NFT from their wallet). The admin does **not** need to sign anything here.
     - **Submit**: The transaction is submitted. If all conditions are correct, the validator will approve the spending and burning.

   After this transaction, on-chain:
   - The script UTXO is gone (spent).
   - The NFT is burned (removed from circulation).
   - The user’s wallet now has their TALOS back (with whatever penalty deducted) and the admin’s wallet has received the penalty tokens.
   - The subscription is fully terminated on-chain (no UTXO, no NFT indicating an active sub).

   If the user attempts to withdraw too early without the proper penalty, or without burning the NFT, or without signature, etc., the transaction will be invalid per the script and not be accepted by the chain.

### Production Considerations and Security

We designed the contract with **production mainnet deployment** in mind, using best practices:
- **Deterministic script outcomes**: All branches of logic (deposit vs withdraw) are well-defined. We avoid any dependence on off-chain data beyond what’s provided in transactions. The time logic uses ledger time from transaction validity, which is a standard way to incorporate time in Plutus contracts ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=The%20key%20feature%20here%20is,if%20the%20bounds%20are%20legit)).
- **No floating point or fraction issues**: Penalties are integer percentages of a fixed token count (10,000), which divides cleanly. No fractional tokens will occur. All math is integer and simple, reducing chance of error.
- **Authorized access**: Only the user’s key can trigger their withdrawal, preventing malicious actors from draining contracts they don’t own. The NFT itself is not sufficient to withdraw (we chose to require owner’s signature as well); even if someone stole or received the NFT, they cannot withdraw the deposit without the owner’s private key. (If the use-case wanted subscriptions to be transferable via NFT, we could drop the owner signature requirement and treat the NFT holder as the owner – but that introduces risk if the NFT is lost. We opt for safety of funds.)
- **Atomic penalty enforcement**: The fee to admin is taken in the same transaction as the return to user, under script control. This ensures the admin automatically gets their due and the user cannot avoid penalties. It also means there is no separate trust needed for fee collection; it’s enforced by code.
- **Testing**: We would create unit tests and scenario tests for the validator. For example, test that withdrawing at various times yields the expected outcome, that invalid attempts fail (e.g., wrong NFT, wrong amounts, unauthorized user). Aiken allows writing tests with mocked transactions to simulate these conditions, as shown in their documentation ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=Testing)).
- **Parameterization**: In Aiken, we can compile the script with parameters. We will likely parameterize the admin’s key hash and the TALOS token’s policy ID and asset name. This way, if those ever need to change, a new instance can be compiled easily. The 10,000 amount and time periods could also be constants in the code or parameters if needed (but as fixed requirements, they can be constants).
- **Script size and Plutus version**: The logic is a bit complex (especially time checks), but Aiken is efficient and Plutus V3 allows slightly larger scripts and additional built-ins. We anticipate the compiled script will fit on-chain. We will target Plutus V3 which corresponds to the latest Cardano protocol (supporting reference inputs, inline datums, etc.). The `plutus.json` from Aiken will specify the use of Plutus V3 in the script binary.

## Deployment Plan for Mainnet

Finally, deploying and using the contract on mainnet involves a series of steps:

**1. Implement and Compile the Aiken Contract**: Write the contract in Aiken, including the validator logic as described. This will produce:
   - A **compiled Plutus script** (in `.uplc` or `.plutus` format) for the validator. Aiken’s output includes the script hash and possibly a **blueprint** (a JSON with addresses and hashes for easy integration).
   - The **script address** (Bech32) derived from the validator (for the spending part).
   - The **policy ID** for the NFT (which should be the same as the script’s hash if using the combined validator; we confirm this after compilation). In Aiken’s example, the `policy_id` is essentially the validator hash used in the mint context ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=list.find%28inputs%2C%20fn%28input%29%20,own_ref)).

We will ensure to apply the admin and token parameters. For instance, in Aiken one can do `aiken build` with parameters or use `apply_params` to inject the admin key hash and TALOS policy ID into the script before finalizing the address ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=const%20blueprint%20%3D%20JSON.parse%28fs.readFileSync%28,%7D%2C%20undefined%2C%200%20%29.address)).

**2. Testing on Testnet**: Before mainnet, deploy on a Cardano testnet (e.g., Preview or Preprod):
   - Fund a test wallet with test ADA and some test TALOS tokens (we’d have to mint test versions of TALOS if TALOS is not on testnet).
   - Try the subscription flow: locking tokens and minting NFT, then different withdrawal scenarios. Use Aiken’s off-chain tooling or a library like *Mesh* or *Lucid* to build transactions. (Aiken’s tutorial shows integration with these for frontend ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=,%E2%98%85)) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=When%20encountering%20an%20unfamiliar%20syntax,for%20details%20and%20extra%20examples)).)
   - Verify that the contract behaves correctly and the NFT and penalty logic work. Adjust code if any issue arises (e.g., off-by-one day issues).

**3. Mainnet Deployment**:
   - **Distribute the Script Address**: Once the script is ready, announce the **subscription address** where users should send their 10,000 TALOS (via the specialized transaction, not just a simple send—users will likely interact through a UI that constructs the proper transaction with minting, rather than manually through a wallet).
   - **Reference Script (Optional but recommended)**: To optimize transaction size and fees, we can utilize Cardano’s reference script feature (CIP-33). The admin can publish a **reference script UTXO** on-chain containing the validator. For example, the admin submits a transaction with an output to a script address carrying the full script as a reference. Thereafter, users’ transactions don’t need to include the whole script each time; they can point to this reference. This is especially useful for the **spend transactions** (withdrawals) to avoid including the validator in every tx, and similarly, the NFT minting policy can be referenced if needed. Plutus V3 supports reference scripts for both spending and minting.
   - **Front-end / Wallet Integration**: Provide a user-friendly interface (dApp or instructions for cardano-cli) for users to subscribe. This will abstract the complexity of datum and minting. For instance, a web dApp could connect to the user’s wallet, then:
       - On “Subscribe”: automatically create and submit the transaction that calls the script address, attaches datum, and mints the NFT. The user just confirms sending 10,000 TALOS.
       - On “Unsubscribe” or “Withdraw”: automatically determine the penalty (based on current date vs start date, which it can fetch from the datum on chain), then construct the transaction to withdraw, burn NFT, and send fees. The user just confirms the transaction in their wallet.
   - **Monitoring and Maintenance**: The admins should monitor the UTXOs at the script address. Over time, many UTXOs (one per active subscription) could accumulate. This is fine (the EUTxO model can handle many UTXOs). Each is independent, so multiple users can subscribe/withdraw in parallel without contention. If the script address starts accumulating too many expired UTXOs (users who never withdrew after 30 days), the team might consider a cleanup policy (not covered here, but could involve reminding users or eventually adding a governance to reclaim unwithdrawn tokens after very long periods).
   - **Security Audit**: Given this is a financial smart contract, it should be audited. We have designed it using known patterns (time-locked vesting ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=and%20,)), NFT-guarded assets ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=In%20the%20context%20of%20this,NFT%20as%20a%20gift%20card)), etc.), but an audit may catch edge cases.

**4. Handling Off-chain Fallbacks**:
   - Document a process for verifying subscriptions off-chain. For example: *“If for any reason the on-chain script is inaccessible, users can prove their subscription by showing ownership of the subscription NFT and/or proving they sent 10,000 TALOS to the contract. In emergency, the admin can verify the user’s address holds the NFT (via Cardano explorer) and temporarily grant access.”* This ensures business continuity even if contract interactions are paused.
   - Also have a plan for contract upgrades: If a new version of the contract is needed (say TALOS policy changes or a bug fix), you would deploy a new script address and direct new subscriptions there, possibly allowing existing ones to migrate or just naturally expire on the old contract.

### Aiken Code Snippets and Assumptions

To solidify, here are illustrative Aiken code snippets reflecting parts of the above logic (note these are for demonstration and would need integration into the full validator):

- **Datum Type (Aiken)**:
  ```rust
  struct SubscriptionDatum {
      owner: VerificationKeyHash,
      start_time: Time // Could be Int representing POSIX milliseconds
  }
  ```
  This is the datum containing the owner key hash and start time.

- **Validator Declaration**:
  ```rust
  validator subscription(admin: VerificationKeyHash, talosPolicy: PolicyId, talosName: AssetName) {
      // spending validator
      spend(datum: SubscriptionDatum, _redeemer: Data, _self: OutputReference, tx: Transaction) -> Bool {
          // ... spending logic as described ...
      }

      // minting policy
      mint(action: MintAction, policy_id: PolicyId, tx: Transaction) -> Bool {
          when action is {
              MintAction::Subscribe -> {
                  // enforce one NFT minted
                  let minted = tx.mint |> assets.tokens(policy_id) |> dict.to_pairs();
                  expect [Pair(tokenName, amount)] = minted;
                  enforce amount == 1;
                  // enforce deposit output present
                  enforce list.any(tx.outputs, fn(out) {
                      out.address.payment_credential == Script(policy_id) &&
                      assets.value_of(out.value, talosPolicy, talosName) == 10000
                  });
                  // Optionally enforce tokenName structure or uniqueness here
                  True
              }
              MintAction::Unsubscribe -> {
                  // enforce burning one NFT
                  let burned = tx.mint |> assets.tokens(policy_id) |> dict.to_pairs();
                  expect [Pair(tokenName, amount)] = burned;
                  enforce amount == -1;
                  True
              }
          }
      }
  }
  ```
  In the above:
  - `admin`, `talosPolicy`, `talosName` are parameters we’ll supply (admin’s key hash, TALOS policy ID and token name).
  - `MintAction` is a custom redeemer type we define (e.g. `enum MintAction { Subscribe; Unsubscribe }`). The redeemer in the minting part of the transaction will specify which branch to run.
  - The `spend` part will utilize `admin` for finding admin output and `talosPolicy/talosName` to identify tokens in outputs.

- **Time and Penalty in spend** (conceptual):
  ```rust
  // inside spend validator:
  let currentTime = tx.validity_range.first;  // assume first bound as current time (valid_from)
  let endTime10 = datum.start_time + 10_days;
  let endTime20 = datum.start_time + 20_days;
  let endTime30 = datum.start_time + 30_days;

  if currentTime < endTime10 {
      // < 10 days elapsed
      checkPenaltyOutputs(tx, datum.owner, admin, talosPolicy, talosName, 3000, 7000);
  } else if currentTime < endTime20 {
      // 10-20 days
      checkPenaltyOutputs(tx, datum.owner, admin, talosPolicy, talosName, 2000, 8000);
  } else if currentTime < endTime30 {
      // 20-30 days
      checkPenaltyOutputs(tx, datum.owner, admin, talosPolicy, talosName, 1000, 9000);
  } else {
      // >=30 days
      checkPenaltyOutputs(tx, datum.owner, admin, talosPolicy, talosName, 0, 10000);
  }

  // ensure owner signed
  enforce key_signed(tx.extra_signatories, datum.owner);
  // ensure NFT burn present for this policy (as shown earlier)
  ```
  The hypothetical `checkPenaltyOutputs` would implement the checks described for output values to admin and owner.

This gives an idea of how the contract is implemented. Some minor details (like converting 30 days to slot numbers or milliseconds for `Time`) would depend on network parameters. On mainnet, 30 days ~ 2,592,000 seconds. If using slots (with 1 sec slot), that many slots. In a POSIX millisecond format, 30 days = 2,592,000,000 ms. We can define a constant or compute it. Our code can use those constants to compare with `tx.validity_range`.

### Conclusion

With the above architecture, we fulfill all requirements: **10,000 TALOS locked for 30 days** enforced by contract, an **NFT issues as on-chain proof** of subscription, the ability to **withdraw early with penalties** automatically paid to **admin**, and a secure flow on Cardano mainnet. The use of Aiken and Plutus V3 features like inline datums and time checks ensures a robust, auditable, and efficient implementation ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=The%20key%20feature%20here%20is,if%20the%20bounds%20are%20legit)). The off-chain infrastructure complements the on-chain logic to provide a seamless user experience (e.g., automatically calculating penalties and constructing transactions). 

By following this plan – writing the contract in Aiken, testing thoroughly, deploying with reference scripts, and building user-friendly transaction scripts – the $TALOS token subscription system will operate trustlessly and transparently on Cardano, with on-chain tracking via NFTs and clear recourse for both users and admins in any scenario. 

**Sources:**

- Aiken Gift Card example – demonstrates locking assets and minting an NFT “gift card” to redeem them ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=In%20the%20context%20of%20this,NFT%20as%20a%20gift%20card)), a pattern we adapted for subscriptions.
- Aiken Vesting example – shows time-locked withdrawal using validity intervals and required signatures ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=key_signed%28tx.extra_signatories%2C%20datum.owner%29%2C%20and%20,)) ([Aiken | Vesting](https://aiken-lang.org/example--vesting/mesh#:~:text=The%20key%20feature%20here%20is,if%20the%20bounds%20are%20legit)), which informed our time-based penalty checks.
- Aiken Language Reference – for multi-handler validators (spend + mint) and asset handling ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=expect%20Some%28own_input%29%20%3D%20list,output_reference%20%3D%3D%20own_ref)) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=%7C)).
