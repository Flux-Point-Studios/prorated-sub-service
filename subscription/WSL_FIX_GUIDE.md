# WSL Terminal Hang Prevention Guide

## Common Causes of WSL Hangs

1. **Stuck apt/dpkg processes** - Most common issue
2. **DNS resolution problems** - Can't reach package servers
3. **WSL2 memory issues** - Insufficient resources
4. **Windows Defender interference** - Scanning WSL files

## Prevention Steps

### 1. Configure WSL Memory (Create/Edit `.wslconfig`)
Create `C:\Users\<YourUsername>\.wslconfig`:
```ini
[wsl2]
memory=4GB
processors=2
localhostForwarding=true
```

### 2. Fix DNS Issues
In WSL, create `/etc/wsl.conf`:
```bash
sudo nano /etc/wsl.conf
```
Add:
```ini
[network]
generateResolvConf = false
```

Then set Google DNS:
```bash
sudo rm /etc/resolv.conf
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo bash -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'
sudo chattr +i /etc/resolv.conf
```

### 3. Disable Windows Path Integration (Optional)
This can prevent some hanging issues:
```bash
sudo nano /etc/wsl.conf
```
Add:
```ini
[interop]
appendWindowsPath = false
```

### 4. Fix Stuck apt Processes
If apt hangs, run these in order:
```bash
# Kill stuck processes
sudo killall -9 apt apt-get dpkg
sudo rm /var/lib/apt/lists/lock
sudo rm /var/cache/apt/archives/lock
sudo rm /var/lib/dpkg/lock*
sudo dpkg --configure -a
sudo apt update
```

## Quick Health Check Script

Create `wsl_health_check.sh`:
```bash
#!/bin/bash
echo "=== WSL Health Check ==="
echo "1. DNS Test:"
nslookup google.com || echo "DNS FAILED"
echo ""
echo "2. APT Test:"
sudo apt update --dry-run || echo "APT FAILED"
echo ""
echo "3. Memory:"
free -h
echo ""
echo "4. Disk Space:"
df -h /
```

## For Your Cardano Testing

### Avoid apt completely - You already have the tools!
```bash
# Check tools are installed
which cardano-cli && echo "✓ cardano-cli installed"
which aiken && echo "✓ aiken installed"
which python3 && echo "✓ python3 installed"
which bc && echo "✓ bc installed"
```

### Use Python instead of jq (if needed)
The `jq.py` script I created works as a replacement.

## Quick Test Commands

From PowerShell:
```powershell
# Test WSL is responsive
wsl echo "WSL works!"

# Run your contract status check
wsl python3 /mnt/c/GitHubRepos/prorated-sub-service/subscription/quick_check.py

# Run extend test
wsl bash -c "cd /mnt/c/GitHubRepos/prorated-sub-service/subscription && ./test_1_extend.sh"
```

## If WSL Hangs Again

1. From PowerShell: `wsl --shutdown`
2. Wait 10 seconds
3. Try again

## Alternative: Use WSL1 (More Stable)
```powershell
# Check current version
wsl -l -v

# Convert to WSL1 if needed
wsl --set-version Ubuntu 1
``` 