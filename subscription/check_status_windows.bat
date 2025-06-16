@echo off
echo Running contract status check...
wsl.exe -e bash -c "cd /mnt/c/GitHubRepos/prorated-sub-service/subscription && python3 quick_check.py"
pause 