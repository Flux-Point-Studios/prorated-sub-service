/**
 * Sample script for creating a subscription
 * 
 * This demonstrates how to create a transaction that:
 * 1. Locks 10,000 AGENT in the contract
 * 2. Mints a subscription NFT
 * 
 * Note: This is a skeleton and needs to be integrated with a Cardano 
 * transaction library like Lucid.
 */

import { Lucid, Blockfrost, Data, Assets } from 'lucid-cardano';

// Configuration (would be loaded from environment variables)
const BLOCKFROST_API_KEY = 'YOUR_BLOCKFROST_API_KEY';
const BLOCKFROST_URL = 'https://cardano-preprod.blockfrost.io/api/v0'; // Preprod for testing

// Smart contract details
const SUBSCRIPTION_SCRIPT_CBOR = 'SUBSCRIPTION_PLUTUS_SCRIPT_CBOR';
const SUBSCRIPTION_ADDRESS = 'SUBSCRIPTION_ADDRESS';
const AGENT_POLICY_ID = 'AGENT_POLICY_ID';
const AGENT_ASSET_NAME = '4147454e54'; // Hex for 'AGENT'

// Amount of AGENT to lock
const SUBSCRIPTION_AMOUNT = 10000n;

/**
 * Create a subscription by locking 10,000 AGENT and minting an NFT
 * @param {string} walletAddress - User's wallet address
 * @param {PrivateKey} privateKey - User's private key for signing
 */
async function createSubscription(walletAddress, privateKey) {
  try {
    // Initialize Lucid with Blockfrost provider
    const lucid = await Lucid.new(
      new Blockfrost(BLOCKFROST_URL, BLOCKFROST_API_KEY),
      'Preprod',
    );
    
    // Set the user's wallet
    lucid.selectWalletFromPrivateKey(privateKey);
    
    // Define the subscription datum
    const datumSchema = Data.Object({
      owner: Data.Bytes(), // User's verification key hash
      start_time: Data.Integer(), // Current time in milliseconds
    });
    
    // Get user's verification key hash
    const userVkh = lucid.utils.getAddressDetails(walletAddress).paymentCredential.hash;
    
    // Create datum with current time
    const currentTimeMs = BigInt(Date.now());
    const datum = {
      owner: userVkh,
      start_time: currentTimeMs,
    };
    
    // Datum CBOR representation
    const datumCbor = Data.to(datum, datumSchema);
    
    // Create NFT name (using a combination of user's key hash and timestamp for uniqueness)
    const nftName = `Sub_${userVkh.slice(0, 8)}_${currentTimeMs}`;
    
    // Assets to lock in the contract
    const agentAsset = {};
    agentAsset[`${AGENT_POLICY_ID}${AGENT_ASSET_NAME}`] = SUBSCRIPTION_AMOUNT;
    
    // Create the transaction
    const tx = await lucid
      .newTx()
      // Add the lockup output with datum
      .payToContract(
        SUBSCRIPTION_ADDRESS,
        { inline: datumCbor },
        { [AGENT_POLICY_ID + AGENT_ASSET_NAME]: SUBSCRIPTION_AMOUNT }
      )
      // Mint the subscription NFT to user's wallet
      .mintAssets({
        [SUBSCRIPTION_SCRIPT_CBOR + Buffer.from(nftName).toString('hex')]: 1n,
      }, Data.void()) // Redeemer would be MintAction::Subscribe in the actual implementation
      .complete();
    
    // Sign the transaction
    const signedTx = await tx.sign().complete();
    
    // Submit the transaction
    const txHash = await signedTx.submit();
    
    console.log(`Subscription created! Transaction hash: ${txHash}`);
    console.log(`NFT Name: ${nftName}`);
    
    return txHash;
  } catch (error) {
    console.error('Error creating subscription:', error);
    throw error;
  }
}

// Example usage:
// createSubscription('addr_test1...', privateKey); 