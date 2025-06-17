# Files to Commit

## CRITICAL: Final Validator Fixes for Aiken v1.1.17
- **subscription_spend.ak** - Fixed for Plutus V3 with correct Unit literal `()`
- **subscription_mint.ak** - Fixed for Plutus V3 with correct Unit literal `()`
- **aiken.toml** - Updated for v1.1.17 compatibility

## Run cleanup first:
```bash
cd subscription
chmod +x cleanup_test_artifacts.sh
./cleanup_test_artifacts.sh
```

## Core files to commit:

### Validator Fixes (CRITICAL - FINAL VERSION)
- validators/subscription_spend.ak
- validators/subscription_mint.ak
- aiken.toml
- FIX_AND_REBUILD_INSTRUCTIONS.md

### Test Scripts
- test_0_initial_merchant_claim.sh
- test_1_extend.sh  
- test_2_merchant_withdraw.sh
- test_3_unsubscribe.sh
- test_4_subscriber_withdraw.sh

### Helper Scripts
- setup_env.sh
- blockfrost_query.sh
- check_status.sh
- quick_check.py
- jq.py

### Windows Support
- RunTests.ps1
- check_status_windows.bat

### Documentation
- TEST_GUIDE.md
- WSL_FIX_GUIDE.md
- NEW_TEST_FILES_SUMMARY.md
- COMMIT_SUMMARY.md (this file)

### Configuration
- .gitignore (updated)

## Git commands:
```bash
# Add validator fixes
git add validators/subscription_spend.ak validators/subscription_mint.ak aiken.toml

# Add test scripts and documentation
git add test_*.sh
git add setup_env.sh blockfrost_query.sh check_status.sh
git add *.py RunTests.ps1 *.bat
git add *.md
git add .gitignore cleanup_test_artifacts.sh

# Commit
git commit -m "Fix validators for Plutus V3 with Aiken v1.1.17

CRITICAL VALIDATOR FIXES:
- Fixed subscription_spend.ak and subscription_mint.ak for Plutus V3
- Removed explicit return type annotations from validator handlers  
- Changed 'unit' to '()' (correct Unit literal for Aiken v1.1.17)
- Updated aiken.toml for v1.1.17 compatibility
- Validators now properly return BuiltinUnit (required by CIP-117)

COMPREHENSIVE TEST SUITE:
- Initial merchant claim test (test_0) - Claims service fee
- Extend subscription test (test_1) - Add installments  
- Merchant withdrawal test (test_2) - Claim from installments
- Unsubscribe test (test_3) - Early cancellation with proration
- Subscriber withdrawal test (test_4) - Claim after expiry
- Helper scripts for Blockfrost integration
- Python-based jq replacement for WSL compatibility
- PowerShell menu for Windows users
- Comprehensive documentation and guides"

# Push
git push origin main
```

## Test Commands:
After committing, test locally:
```bash
cd subscription
aiken check      # Should show 0 errors
aiken build --target v3
```

Then in Demeter:
```bash
git pull origin main
aiken build --target v3
# Test merchant claim transaction
```

## Note about .env:
The .env file contains your Blockfrost API key. You may want to:
1. Add it to .gitignore if it contains sensitive data
2. Or create a .env.example with placeholder values 