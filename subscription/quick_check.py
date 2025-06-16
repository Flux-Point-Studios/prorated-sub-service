#!/usr/bin/env python3
import json
import subprocess
import os
from datetime import datetime

# Load environment
SCRIPT_ADDR = "addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf"
SCRIPT_TX = "85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0"
BLOCKFROST_KEY = "mainnetXdMvEPp07a5GgSWtpSqUytnmtR4OvJzr"

print("=== Quick Contract Status Check ===")
print(f"Script Address: {SCRIPT_ADDR[:30]}...")
print(f"Script UTxO: {SCRIPT_TX}")
print()

# Query Blockfrost
import urllib.request
import urllib.error

url = f"https://cardano-mainnet.blockfrost.io/api/v0/addresses/{SCRIPT_ADDR}/utxos"
headers = {"project_id": BLOCKFROST_KEY}

try:
    req = urllib.request.Request(url, headers=headers)
    response = urllib.request.urlopen(req)
    utxos = json.loads(response.read())
    
    if utxos:
        utxo = utxos[0]  # Get first UTxO
        
        # Parse amounts
        ada = 0
        agent = 0
        nft = 0
        
        for amount in utxo['amount']:
            if amount['unit'] == 'lovelace':
                ada = int(amount['quantity']) / 1_000_000
            elif amount['unit'] == '97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec54616c6f73':
                agent = int(amount['quantity'])
            elif amount['unit'] == 'efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb4147454e545f5355425f4e4654':
                nft = int(amount['quantity'])
        
        print("💰 Current Value:")
        print(f"  - ADA: {ada}")
        print(f"  - AGENT: {agent:,}")
        print(f"  - NFT: {nft}")
        print()
        
        # Get inline datum
        if utxo.get('inline_datum'):
            datum = utxo['inline_datum']
            if datum and 'fields' in datum:
                fields = datum['fields']
                
                # Parse subscription dates
                sub_end = fields[4]['int'] if len(fields) > 4 else 0
                installments = len(fields[6]['list']) if len(fields) > 6 else 0
                
                # Convert milliseconds to seconds
                sub_end_date = datetime.fromtimestamp(sub_end / 1000)
                now = datetime.now()
                
                print("📅 Subscription Status:")
                print(f"  - Ends: {sub_end_date}")
                print(f"  - Active: {'Yes' if now < sub_end_date else 'No (Expired)'}")
                print(f"  - Installments: {installments}")
                print()
                
                print("🎯 Next Steps:")
                if installments == 0:
                    print("  1. Run test_1_extend.sh to add an installment")
                else:
                    print("  1. Run test_2_merchant_withdraw.sh to claim payment")
                    print("  2. Or run test_3_unsubscribe.sh to cancel early")
        
    else:
        print("❌ No UTxOs found at script address")
        
except urllib.error.HTTPError as e:
    print(f"❌ Blockfrost API error: {e.code} - {e.reason}")
except Exception as e:
    print(f"❌ Error: {e}")

print("\nTo run test scripts, use:")
print("  ./test_1_extend.sh        - Add payment installment")
print("  ./test_2_merchant_withdraw.sh - Merchant claims payment")
print("  ./test_3_unsubscribe.sh   - Cancel subscription")
print("  ./test_4_subscriber_withdraw.sh - Withdraw after expiry") 