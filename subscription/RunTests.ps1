# AGENT Subscription Contract Test Runner
# Run from PowerShell with: .\RunTests.ps1

Write-Host "=== AGENT Subscription Contract Test Runner ===" -ForegroundColor Cyan
Write-Host ""

# Function to run WSL commands safely
function Run-WSLCommand {
    param($Command, $Description)
    
    Write-Host "→ $Description" -ForegroundColor Yellow
    # Fixed: Set PATH and create jq alias
    $setupCmd = "cd /mnt/c/GitHubRepos/prorated-sub-service/subscription && "
    $setupCmd += "export PATH=/home/decimalist/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && "
    $setupCmd += "alias jq='python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/jq.py' && "
    $setupCmd += "export -f jq 2>/dev/null ; "
    
    $result = wsl bash -c "$setupCmd$Command" 2>&1
    Write-Host $result
    Write-Host ""
}

# Menu
Write-Host "Select an option:" -ForegroundColor Green
Write-Host "0. Initial Merchant Claim (service fee from first deposit)"
Write-Host "1. Check Contract Status"
Write-Host "2. Run Extend Test (Add installment)"
Write-Host "3. Run Merchant Withdraw Test (requires installments)"
Write-Host "4. Run Unsubscribe Test (Cancel early)"
Write-Host "5. Run Subscriber Withdraw Test (After expiry)"
Write-Host "6. Quick Status (Python)"
Write-Host "7. Exit"
Write-Host ""

$choice = Read-Host "Enter choice (0-7)"

switch ($choice) {
    "0" {
        Write-Host "This will claim the merchant's service fee from the initial 10k AGENT deposit" -ForegroundColor Yellow
        Write-Host "Service fee is typically 1,000 AGENT (10%)" -ForegroundColor Cyan
        $confirm = Read-Host "Continue? (y/n)"
        if ($confirm -eq "y") {
            Run-WSLCommand "chmod +x test_0_initial_merchant_claim.sh && ./test_0_initial_merchant_claim.sh" "Running Initial Merchant Claim..."
        }
    }
    "1" {
        Run-WSLCommand "python3 quick_check.py" "Checking contract status..."
    }
    "2" {
        Write-Host "This will:" -ForegroundColor Yellow
        Write-Host "- Lock another 10,000 AGENT tokens"
        Write-Host "- Extend subscription by 30 days"
        Write-Host "- Add an installment for merchant to claim"
        Write-Host ""
        $confirm = Read-Host "Continue? (y/n)"
        if ($confirm -eq "y") {
            Run-WSLCommand "chmod +x test_1_extend.sh && ./test_1_extend.sh" "Running Extend test..."
        }
    }
    "3" {
        Write-Host "This will attempt to withdraw merchant's payment from installments" -ForegroundColor Yellow
        Write-Host "NOTE: Requires at least one installment (run option 2 first!)" -ForegroundColor Red
        $confirm = Read-Host "Continue? (y/n)"
        if ($confirm -eq "y") {
            Run-WSLCommand "chmod +x test_2_merchant_withdraw.sh && ./test_2_merchant_withdraw.sh" "Running Merchant Withdraw test..."
        }
    }
    "4" {
        Write-Host "This will cancel the subscription early with proration" -ForegroundColor Yellow
        Write-Host "WARNING: This burns the NFT!" -ForegroundColor Red
        $confirm = Read-Host "Continue? (y/n)"
        if ($confirm -eq "y") {
            Run-WSLCommand "chmod +x test_3_unsubscribe.sh && ./test_3_unsubscribe.sh" "Running Unsubscribe test..."
        }
    }
    "5" {
        Write-Host "This withdraws remaining tokens after subscription expires" -ForegroundColor Yellow
        Write-Host "WARNING: This burns the NFT!" -ForegroundColor Red
        $confirm = Read-Host "Continue? (y/n)"
        if ($confirm -eq "y") {
            Run-WSLCommand "chmod +x test_4_subscriber_withdraw.sh && ./test_4_subscriber_withdraw.sh" "Running Subscriber Withdraw test..."
        }
    }
    "6" {
        Run-WSLCommand "python3 quick_check.py" "Running quick status check..."
    }
    "7" {
        Write-Host "Exiting..." -ForegroundColor Gray
        exit
    }
    default {
        Write-Host "Invalid choice!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") 