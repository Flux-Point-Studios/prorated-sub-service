# Files to Commit

## Run cleanup first:
```bash
cd subscription
chmod +x cleanup_test_artifacts.sh
./cleanup_test_artifacts.sh
```

## Core files to commit:

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
# Add test scripts
git add test_*.sh
git add setup_env.sh blockfrost_query.sh check_status.sh
git add *.py RunTests.ps1 *.bat
git add *.md
git add .gitignore cleanup_test_artifacts.sh

# Commit
git commit -m "Add comprehensive test suite for AGENT subscription contract

- Initial merchant claim test (test_0)
- Extend subscription test (test_1)
- Merchant withdrawal test (test_2)
- Unsubscribe test (test_3)
- Subscriber withdrawal test (test_4)
- Helper scripts for Blockfrost integration
- Python-based jq replacement for WSL compatibility
- PowerShell menu for Windows users
- Documentation and guides"

# Push
git push origin main
```

## Note about .env:
The .env file contains your Blockfrost API key. You may want to:
1. Add it to .gitignore if it contains sensitive data
2. Or create a .env.example with placeholder values 