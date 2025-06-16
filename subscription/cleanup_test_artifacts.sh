#!/bin/bash

echo "=== Cleaning up test artifacts ==="
echo

# Remove transaction files
echo "Removing transaction files..."
rm -f *.txbody *.tx.signed *.cbor

# Remove temporary JSON files (but keep important ones)
echo "Removing temporary JSON files..."
rm -f cost.json current_datum.json new_datum.json old_datum.json new_inst.json
rm -f extend.redeemer.json merchant_claim.redeemer.json initial_claim.redeemer.json
rm -f script_utxos.json blockfrost_utxos.json pparams_blockfrost.json
rm -f new_datum.hash
rm -f utxo.json utxos.json script_utxo.json unit.json datum.json
rm -f mint.txbody mint_dbg.txbody
rm -f tx.raw tx.signed

# Remove large downloaded files
echo "Removing large downloaded files..."
rm -f *.tar.gz cardano-node-*.tar.gz*

# Remove empty files
echo "Removing empty files..."
find . -type f -size 0 -delete

echo
echo "Cleanup complete!"
echo
echo "Important files preserved:"
echo "  - All test scripts (test_*.sh)"
echo "  - Helper scripts (setup_env.sh, blockfrost_query.sh, etc.)"
echo "  - Python scripts (*.py)"
echo "  - Documentation (*.md)"
echo "  - Configuration (aiken.json, plutus.json, subscribe.json, pparams.json)"
echo "  - Artifacts directory"
echo
echo "Ready to commit!" 