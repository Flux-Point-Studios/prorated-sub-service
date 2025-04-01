# Step-by-Step Guide for Compiling in Ubuntu Terminal

Since we're experiencing issues with the PowerShell/WSL environment, here's a guide to compile the project in a dedicated Ubuntu terminal:

## 1. Install Aiken in Ubuntu

Open a dedicated Ubuntu terminal window and run:

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

## 2. Copy Project Files

Clone the repository or copy files to your Ubuntu environment:

```bash
# Create a directory for the project
mkdir -p ~/talos-subscription

# If you have Git access to the repo
git clone https://github.com/talos/prorated-sub-service.git ~/talos-subscription

# Or copy files manually if needed
```

## 3. Check Project Structure

Ensure your project structure follows the Aiken requirements:

```bash
cd ~/talos-subscription

# Create the necessary directories if they don't exist
mkdir -p lib/subscription validators

# If you're copying files manually, make sure to copy:
# - aiken.toml
# - lib/subscription.ak
# - validators/subscription.ak
# - validators/subscription_test.ak
```

## 4. Compile and Test the Project

Use Aiken commands to compile and test:

```bash
# Check the Aiken code
aiken check

# Build the project
aiken build

# Generate the Plutus script
aiken blueprint
```

## 5. Fix Common Issues

If you encounter syntax errors, you may need to update:

1. Validator syntax:
   - Aiken now requires separate validators for different purposes
   - Use `validator name(params) { fn handler() {} }` syntax

2. ByteArray literals:
   - Strings must be hex-encoded: `#"talos"` should be `#"74616c6f73"`

3. Enum access:
   - Change `MintAction::Subscribe` to `MintAction.Subscribe`
   - Change `ScriptPurpose::Spend` to `ScriptPurpose.Spend`

## 6. After Successful Compilation

After successful compilation, you'll get:

1. A `plutus.json` file containing the compiled contracts
2. Blueprint information with validator addresses and policy IDs

You can copy these back to your Windows environment for further development.

## Final Note

The code has been updated in the repository to use the current Aiken syntax. The main changes were:

1. Split the combined validator into separate spending and minting validators
2. Fixed ByteArray literals for text
3. Updated enum access syntax 
4. Qualified imports for transaction types

These changes should make the code compatible with the latest version of Aiken. 