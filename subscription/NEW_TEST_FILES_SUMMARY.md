# New Test Files Created

## Core Test Scripts
1. **test_0_initial_merchant_claim.sh** - Claims initial service fee (for Demeter with local node)
2. **test_1_extend.sh** - Extends subscription by adding installment
3. **test_2_merchant_withdraw.sh** - Merchant withdraws from installments  
4. **test_3_unsubscribe.sh** - Early cancellation with proration
5. **test_4_subscriber_withdraw.sh** - Withdraw after expiry

## Helper Scripts
- **setup_env.sh** - Sets environment variables
- **blockfrost_query.sh** - Blockfrost API helper functions
- **check_status.sh** - Checks contract status
- **quick_check.py** - Python-based quick status checker
- **jq.py** - Python replacement for jq command

## Windows/PowerShell Support
- **RunTests.ps1** - PowerShell menu for running tests
- **check_status_windows.bat** - Windows batch file for status
- **run_initial_claim.bat** - Windows batch for initial claim

## Alternative Versions
- **test_0_initial_merchant_claim_blockfrost.sh** - Blockfrost version (incomplete)
- **check_and_prepare_initial_claim.sh** - Simplified preparation script
- **test_initial_claim.py** - Python version showing transaction details

## Documentation
- **TEST_GUIDE.md** - Testing guide
- **WSL_FIX_GUIDE.md** - WSL troubleshooting guide
- **VALIDATOR_TESTING_STATUS.md** - Detailed testing notes from Demeter

## Files to NOT commit (generated during testing):
- *.json (except aiken.json, plutus.json)
- *.cbor
- *.txbody
- *.tx.signed
- *.tar.gz
- cost.json
- current_datum.json
- new_datum.json
- etc. 