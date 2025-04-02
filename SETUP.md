# TALOS Subscription Service Setup Guide

This guide provides instructions for setting up and compiling the TALOS Subscription Service smart contract.

## Environment Setup Options

### Option 1: Ubuntu/Linux Environment (Recommended)

```bash
# Update package lists
sudo apt update

# Install required dependencies
sudo apt install -y curl git build-essential

# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Source Nix in your current shell
. ~/.nix-profile/etc/profile.d/nix.sh

# Configure Nix for flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Install Aiken
nix profile install github:aiken-lang/aiken

# Verify installation
aiken --version
```

### Option 2: Windows with WSL

1. Install WSL if not already installed:
   ```powershell
   wsl --install
   ```

2. Launch Ubuntu in WSL and follow the Ubuntu instructions above.

3. Access your Windows files from WSL at `/mnt/c/`.

## Compiling the Project

From the root of the project directory:

```bash
# Navigate to the subscription folder
cd subscription

# Check the Aiken code
aiken check

# Build the project
aiken build

# Generate the Plutus script and blueprint
aiken blueprint
```

Upon successful completion, you'll see output confirming the tests have passed:

```
Compiling talos/subscription 0.1.0 (.)
Resolving talos/subscription
  Fetched 1 package in 0.25s from cache
Compiling aiken-lang/stdlib 2.1.0 (./build/packages/aiken-lang-stdlib)
Collecting all tests scenarios across all modules
  Testing ...

┍━ subscription_prorated ━━━━━━━━━━━━━━━━━━━━━━━━━━━
│ PASS [mem: 7384, cpu: 2440461] subscription_active
┕━━━━━━━━━━━━━━━━━━━━━ 1 tests | 1 passed | 0 failed

  Summary 1 check, 0 errors, 0 warnings
```

## Troubleshooting

### Common Issues

1. **WSL Terminal Issues**
   - If encountering issues with WSL terminal, consider using a dedicated Ubuntu terminal

2. **Aiken Syntax Errors**
   - Verify that the code uses current Aiken syntax (≥ 1.0.0)
   - Check pattern matching syntax in particular

3. **Path Issues**
   - Ensure the correct directory structure as shown in the README.md

## Next Steps After Compilation

After successful compilation:

1. The `plutus.json` file will contain the compiled validator contracts
2. The blueprint information will include validator addresses and policy IDs

You'll need to update these values in your off-chain code before deployment. 