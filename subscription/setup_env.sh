#!/bin/bash
# Script addresses and transaction references
export SCRIPT_ADDR=$(cat artifacts-mainnet/spend.addr)
export SCRIPT_TX=85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0

# Policy IDs and asset names
export POLICY_ID=efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb
export ASSET_HEX=4147454e545f5355425f4e4654
export AGENT_POLICY_ID=97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec
export AGENT_ASSET_NAME=54616c6f73

# Wallet addresses
export PAYMENT_ADDR=$(cat wallets/admin/payment.addr)
export MERCHANT_ADDR=addr1qywdfemwpzqnku8zpskp2p52j0uwwwsg8au2qce7ju2ahqrh4a0788juue7vn5yg674zdk4zxq26xqg2swrj8vvzcdjqqgegwj

# Key hashes
export ADMIN_KEY_HASH=$(cardano-cli address key-hash --payment-verification-key-file wallets/admin/payment.vkey)
export SUB_KEY_HASH=$(cardano-cli address key-hash --payment-verification-key-file wallets/subscriber/payment.vkey)
export MERCHANT_KEY_HASH=1cd4e76e08813b70e20c2c15068a93f8e73a083f78a0633e9715db80

# Script paths
export SPEND_SCRIPT=artifacts-mainnet/spend_policy.plutus

echo "Environment variables set!" 