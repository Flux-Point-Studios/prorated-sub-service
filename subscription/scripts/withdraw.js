/**
 * Sample script for withdrawing from a subscription
 * 
 * This demonstrates how to create a transaction that:
 * 1. Spends a subscription UTXO
 * 2. Burns the subscription NFT
 * 3. Returns TALOS tokens to the owner with applicable penalty
 * 
 * Note: This is a skeleton and needs to be integrated with a Cardano 
 * transaction library like Lucid.
 */

import { Lucid, Blockfrost, Data, UTxO, Assets } from 'lucid-cardano';

// Configuration (would be loaded from environment variables)
const BLOCKFROST_API_KEY = 'YOUR_BLOCKFROST_API_KEY';
const BLOCKFROST_URL = 'https://cardano-preprod.blockfrost.io/api/v0'; // Preprod for testing

// Smart contract details
const SUBSCRIPTION_SCRIPT_CBOR = 'SUBSCRIPTION_PLUTUS_SCRIPT_CBOR';
const SUBSCRIPTION_ADDRESS = 'SUBSCRIPTION_ADDRESS';
const SUBSCRIPTION_REFERENCE_UTXO = 'REFERENCE_SCRIPT_TXHASH#INDEX'; // For reference script
const TALOS_POLICY_ID = 'TALOS_POLICY_ID';
const TALOS_ASSET_NAME = '54414c4f53'; // Hex for 'TALOS'
const ADMIN_ADDRESS = 'ADMIN_TREASURY_ADDRESS';

// Subscription details
const SUBSCRIPTION_AMOUNT = 10000n;
const DAY_IN_MS = 86400000n; // 24 * 60 * 60 * 1000
const PERIOD_10_DAYS = 10n * DAY_IN_MS;
const PERIOD_20_DAYS = 20n * DAY_IN_MS;
const PERIOD_30_DAYS = 30n * DAY_IN_MS;

/**
 * Calculate the penalty based on elapsed time
 * @param {bigint} startTimeMs - Subscription start time in milliseconds
 * @param {bigint} currentTimeMs - Current time in milliseconds
 * @returns {Object} Object containing admin and user amounts
 */
function calculatePenalty(startTimeMs, currentTimeMs) {
  const elapsed = currentTimeMs - startTimeMs;
  
  if (elapsed < PERIOD_10_DAYS) {
    // Less than 10 days: 30% penalty
    return {
      adminAmount: SUBSCRIPTION_AMOUNT * 30n / 100n,
      userAmount: SUBSCRIPTION_AMOUNT * 70n / 100n
    };
  } else if (elapsed < PERIOD_20_DAYS) {
    // 10-20 days: 20% penalty
    return {
      adminAmount: SUBSCRIPTION_AMOUNT * 20n / 100n,
      userAmount: SUBSCRIPTION_AMOUNT * 80n / 100n
    };
  } else if (elapsed < PERIOD_30_DAYS) {
    // 20-30 days: 10% penalty
    return {
      adminAmount: SUBSCRIPTION_AMOUNT * 10n / 100n,
      userAmount: SUBSCRIPTION_AMOUNT * 90n / 100n
    };
  } else {
    // 30+ days: 0% penalty
    return {
      adminAmount: 0n,
      userAmount: SUBSCRIPTION_AMOUNT
    };
  }
}

/**
 * Withdraw from a subscription
 * @param {string} walletAddress - User's wallet address
 * @param {PrivateKey} privateKey - User's private key for signing
 * @param {string} subscriptionUtxo - UTXO of the subscription to withdraw from
 * @param {string} nftName - Name of the subscription NFT to burn
 */
async function withdrawSubscription(walletAddress, privateKey, subscriptionUtxo, nftName) {
  try {
    // Initialize Lucid with Blockfrost provider
    const lucid = await Lucid.new(
      new Blockfrost(BLOCKFROST_URL, BLOCKFROST_API_KEY),
      'Preprod',
    );
    
    // Set the user's wallet
    lucid.selectWalletFromPrivateKey(privateKey);
    
    // Define the datum schema to parse existing datum
    const datumSchema = Data.Object({
      owner: Data.Bytes(),
      start_time: Data.Integer(),
    });
    
    // Get the subscription UTXO
    const utxos = await lucid.utxosByOutRef([subscriptionUtxo]);
    if (utxos.length === 0) {
      throw new Error('Subscription UTXO not found');
    }
    
    const utxo = utxos[0];
    if (!utxo.datum) {
      throw new Error('Datum not found on UTXO');
    }
    
    // Parse the datum
    const datum = Data.from(utxo.datum, datumSchema);
    
    // Get current time
    const currentTimeMs = BigInt(Date.now());
    
    // Calculate penalty based on elapsed time
    const { adminAmount, userAmount } = calculatePenalty(datum.start_time, currentTimeMs);
    
    // Create a transaction to withdraw
    let tx = lucid.newTx();
    
    // Add the subscription UTXO as input
    tx = tx.collectFrom([utxo], Data.void());
    
    // Use reference script if available
    if (SUBSCRIPTION_REFERENCE_UTXO) {
      tx = tx.readFrom([SUBSCRIPTION_REFERENCE_UTXO]);
    }
    
    // Add output for user's tokens (return amount minus penalty)
    tx = tx.payToAddress(walletAddress, {
      [TALOS_POLICY_ID + TALOS_ASSET_NAME]: userAmount
    });
    
    // Add output for admin's tokens (penalty) if there is a penalty
    if (adminAmount > 0n) {
      tx = tx.payToAddress(ADMIN_ADDRESS, {
        [TALOS_POLICY_ID + TALOS_ASSET_NAME]: adminAmount
      });
    }
    
    // Burn the subscription NFT
    tx = tx.mintAssets({
      [SUBSCRIPTION_SCRIPT_CBOR + Buffer.from(nftName).toString('hex')]: -1n
    }, Data.to("Unsubscribe", Data.Enum([Data.Literal("Subscribe"), Data.Literal("Unsubscribe")])));
    
    // Set validity interval to ensure correct time-based validation
    // The start time needs to be the current slot for the transaction to be accepted
    tx = tx.validFrom(Date.now());
    
    // Complete transaction
    const completeTx = await tx.complete();
    
    // Sign the transaction
    const signedTx = await completeTx.sign().complete();
    
    // Submit the transaction
    const txHash = await signedTx.submit();
    
    console.log(`Withdraw successful! Transaction hash: ${txHash}`);
    console.log(`User received: ${userAmount} TALOS`);
    console.log(`Admin received: ${adminAmount} TALOS`);
    console.log(`NFT ${nftName} burned`);
    
    return txHash;
  } catch (error) {
    console.error('Error withdrawing from subscription:', error);
    throw error;
  }
}

// Example usage:
// withdrawSubscription('addr_test1...', privateKey, 'txhash#index', 'Sub_12345678_1234567890123'); 