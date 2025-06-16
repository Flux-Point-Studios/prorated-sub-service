@echo off
echo === Running Initial Merchant Claim Test ===
echo.
echo This will claim the merchant's 1,000 AGENT service fee
echo.
wsl bash -c "cd /mnt/c/GitHubRepos/prorated-sub-service/subscription && source setup_env.sh && export PATH=/home/decimalist/.local/bin:$PATH && cardano-cli conway query utxo --address $(cat artifacts-mainnet/spend.addr) --mainnet"
pause 