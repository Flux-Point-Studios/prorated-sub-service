@echo off
echo Running Extend Test (Add installment)...
echo.
echo This will:
echo - Add another 10,000 AGENT to the contract
echo - Extend subscription by 30 days
echo - Create an installment for merchant to claim
echo.
pause

wsl.exe -e bash -c "cd /mnt/c/GitHubRepos/prorated-sub-service/subscription && export PATH=/home/decimalist/.local/bin:$PATH && chmod +x *.sh && ./test_1_extend.sh"
pause 