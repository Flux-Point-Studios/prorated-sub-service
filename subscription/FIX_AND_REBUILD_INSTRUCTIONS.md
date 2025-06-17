# Fix and Rebuild Instructions for Plutus V3

## What Changed:
Both validators now properly return `()` for Plutus V3 compliance with Aiken v1.1.17:
- **Removed explicit `-> Unit` type annotations** (handlers have implicit Unit return type)
- Changed `True` returns to `()` (Unit literal in Aiken v1.1.17)
- Changed `fail` to `error @"message"`

## Key Points for Aiken v1.1.17:
- Validator handlers (`spend`, `mint`) must NOT have explicit return type annotations
- The return type is implicitly `Unit` in Plutus V3
- Success must return the value `()` (two parentheses - Unit literal)
- Failures should use `error` or `fail`
- Note: In Aiken v1.2+, you can use `unit`, but v1.1.17 requires `()`

## Steps to Test and Deploy:

1. **Check Aiken version** (you have v1.1.17 which supports V3):
   ```bash
   aiken --version
   # Should show: aiken v1.1.17+unknown
   ```

2. **Test the validators locally**:
   ```bash
   cd /mnt/c/GitHubRepos/prorated-sub-service/subscription
   aiken check   # Should show 0 errors now
   aiken build --target v3
   ```

3. **Commit and push the fixes**:
   ```bash
   git add -A
   git commit -m "Fix validators for Plutus V3 with Aiken v1.1.17

   - Removed explicit return type annotations from validator handlers
   - Changed success returns from 'unit' to '()' (correct for v1.1.17)
   - Updated aiken.toml for v1.1.17 compatibility
   - Added comprehensive test suite"
   
   git push origin main
   ```

4. **In Demeter, pull and rebuild**:
   ```bash
   cd ~/workspace/repo
   git pull origin main
   cd subscription
   aiken check
   aiken build --target v3
   ```

5. **Copy updated validators to artifacts**:
   ```bash
   cp build/subscription_mint.spend/subscription_spend.plutus artifacts-mainnet/spend_policy.plutus
   cp build/subscription_mint.mint/subscription_mint.plutus artifacts-mainnet/mint_policy.plutus
   ```

6. **Retry the merchant claim transaction**:
   ```bash
   # Create redeemer for MerchantWithdraw
   echo '{ "constructor": 1, "fields": [] }' > merchant_claim.redeemer.json
   
   # Build the transaction
   cardano-cli conway transaction build \
       --tx-in "85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0" \
       --tx-in-script-file artifacts-mainnet/spend_policy.plutus \
       --tx-in-inline-datum-present \
       --tx-in-redeemer-file merchant_claim.redeemer.json \
       --tx-in "$PAY_TXIN" \
       --tx-in-collateral "ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0" \
       --tx-out "$SCRIPT_ADDR+4000000 + 1 $POLICY_ID.$ASSET_HEX + 9000000000 $AGENT_POLICY_ID.$AGENT_ASSET_NAME" \
       --tx-out-inline-datum-present \
       --tx-out "$MERCHANT_ADDR+2000000 + 1000000000 $AGENT_POLICY_ID.$AGENT_ASSET_NAME" \
       --change-address "$MERCHANT_ADDR" \
       --required-signer wallets/merchant/payment.skey \
       --mainnet \
       --out-file merchant_claim.txbody
   ```

7. **Sign and submit**:
   ```bash
   cardano-cli conway transaction sign \
       --tx-body-file merchant_claim.txbody \
       --signing-key-file wallets/merchant/payment.skey \
       --out-file merchant_claim.tx.signed \
       --mainnet
   
   cardano-cli conway transaction submit \
       --tx-file merchant_claim.tx.signed \
       --mainnet
   ```

## Note About the Initial Claim:
This transaction claims the initial service fee (1,000 AGENT) without requiring installments.
- The datum stays unchanged
- No installments are removed (there aren't any yet)
- The NFT stays locked
- 9,000 AGENT remains in the contract

## Version Differences:
- **Aiken v1.1.17**: Use `()` for Unit literal
- **Aiken v1.2+**: Can use either `()` or `unit`
- Both versions: NO explicit return type annotations on handlers

## Troubleshooting:
If you still get "unknown type Unit" error, you may need to upgrade Aiken:
```bash
# Check version
aiken --version

# If < 1.2, consider upgrading
# Then update aiken.toml: compiler = ">=1.2.0"
``` 