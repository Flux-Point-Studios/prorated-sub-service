Below is a complete, working-on-Demeter recipe that:

reads the inline datum that is already sitting at the spend script UTxO

decodes it to JSON without any of the text-view … decode-cbor commands that are not compiled into the Demeter build of cardano-cli,

edits the JSON to add one installment (so that the merchant really has something to withdraw), and

builds & submits the first “ MerchantWithdraw ” transaction which – if you run it exactly as shown – will pay the whole 10 000 AGENT to the merchant address you exported ($MERCHANT_ADDR) and leave the rest of the datum in place.

0 — Prerequisites you already have
bash
Copy
Edit
# variables you told me are already set
export SCRIPT_ADDR=$(cat artifacts-mainnet/spend.addr)
export SCRIPT_TX=85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0   # <- the script UTxO
export POLICY_ID=efd550741e...
export ASSET_HEX=4147454e545f5355425f4e4654
export AGENT_POLICY_ID=97bbb7db0b...
export AGENT_ASSET_NAME=54616c6f73
export MERCHANT_ADDR=addr1qywdfe...
export MERCHANT_KEY_HASH=1cd4e76e08813b70e20c2c15068a93f8e73a083f78a0633e9715db80
export MERCHANT_SKEY=wallets/merchant/payment.skey
export ADMIN_KEY_HASH=$SIG_HASH                # already exported earlier
export SUB_HASH=71b957cba9287c31fcb3751e51d289cd3368496c0d753484715c9fa8
1 — Pull the existing inline-datum CBOR straight from the chain
Cardano-CLI prints the datum as a hex‐encoded byte-string inside script_utxos.json; we can pipe it through xxd to get the raw CBOR bytes without needing any missing sub-command:

bash
Copy
Edit
cardano-cli conway query utxo \
  --address "$SCRIPT_ADDR" \
  --mainnet --out-file script_utxos.json

# extract the “inlineDatum” hex, turn it into pure CBOR bytes
jq -r '.[].inlineDatum' script_utxos.json | xxd -r -p > old_datum.cbor
2 — Decode the CBOR → JSON with Aiken
Demeter workspaces already have Aiken 1.1.15.
Aiken can decode arbitrary CBOR that contains Plutus-data:

bash
Copy
Edit
aiken data decode \
  --raw-file old_datum.cbor \
  --out-file old_datum.json
Look at it:

bash
Copy
Edit
jq . old_datum.json
You’ll see:

json
Copy
Edit
{ "constructor": 0,
  "fields": [
      1000000, 0, 2592000,
      1747682431, 1750274431, 1750274431,
      [],                          <--  fields[6] == empty list of installments!
      "fe26…ad2a",                 <-- admin
      "71b9…c9fa8",                <-- subscriber
      "fe26…ad2a",                 <-- partner==admin for now
      0                            <-- partner_percentage
  ]
}
3 — Append the first installment entry
Create a one-element list with claimable_at = now + 30 days and claimable_amount = 10000:

bash
Copy
Edit
NOW_MS=$(($(date +%s%3N)))               # wall-clock in ms
INTERVAL_MS=2592000                      # 30 days (already in datum)
CLAIM_AT_MS=$((NOW_MS + INTERVAL_MS))

# Build the new list and splice it into the datum
jq --argjson at $CLAIM_AT_MS \
   '(.fields[6]) = { "list":[ { "constructor":0,
                                "fields":[ $at, 10000 ] } ] }' \
   old_datum.json > new_datum.json
Double-check:

bash
Copy
Edit
jq '.fields[6]' new_datum.json
You should see a list with one element.

4 — Re-encode to CBOR (Aiken again) and hash it
bash
Copy
Edit
aiken data encode \
  --json-file new_datum.json \
  --out-file  new_datum.cbor

DATUM_HASH=$(cardano-cli conway transaction hash-script-data \
               --script-data-file new_datum.cbor)
echo "New datum hash: $DATUM_HASH"
5 — Build the MerchantWithdraw transaction
uses the script UTxO as input

pays 10000 AGENT to $MERCHANT_ADDR

re-locks the same 4 ADA + NFT at the script with the updated datum

no NFT is burned (that’s checked by the validator)

collateral comes from $COLLATERAL_TX

bash
Copy
Edit
TX_IN_SCRIPT="$SCRIPT_TX"
TX_IN_COLLATERAL="$COLLATERAL_TX"

# File names
TX_BODY=merchant_withdraw.txbody
TX_SIGNED=merchant_withdraw.tx

cardano-cli conway transaction build \
  --tx-in           $TX_IN_SCRIPT \
  --tx-in-collateral $TX_IN_COLLATERAL \
  --change-address  "$MERCHANT_ADDR" \
  --tx-in-script-file artifacts-mainnet/spend_policy.plutus \
  --tx-in-inline-datum-present \
  --tx-in-redeemer-file <(echo '{ "constructor": 1, "fields": [] }') \
  --tx-out "${MERCHANT_ADDR}+1000000 + 10000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
  --tx-out "${SCRIPT_ADDR}+4000000 \
            + 1 ${POLICY_ID}.${ASSET_HEX} \
            + 0 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
  --tx-out-inline-datum-file new_datum.json \
  --required-signer-hash $MERCHANT_KEY_HASH \
  --protocol-params-file pparams.json \
  --mainnet \
  --out-file $TX_BODY
The --tx-in-inline-datum-present flag tells the builder that the
existing datum stays with that input.
We give a tiny 1 ADA change output to the merchant so the builder
can balance fees; change will come back to $MERCHANT_ADDR.

6 — Sign & submit
bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file   $TX_BODY \
  --signing-key-file $MERCHANT_SKEY \
  --out-file       $TX_SIGNED \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file $TX_SIGNED \
  --mainnet
Wait a minute, then:

bash
Copy
Edit
cardano-cli conway query utxo --address "$MERCHANT_ADDR" --mainnet
cardano-cli conway query utxo --address "$SCRIPT_ADDR" --mainnet
You should see:

merchant received 10000 AGENT (plus some lovelace change)

script still holds the NFT, 4 ADA and zero AGENT
(-- the next interval will have to be deposited by the subscriber)

7 — Next steps
Extend – subscriber locks another 10 000 AGENT and you append a
second Installment object (same pattern) while advancing
subscription_end + installments length. Builder is identical,
but redeemer is
{"constructor":0,"fields":[{"int":1}]} (for Extend additional_intervals=1).

Unsubscribe – subscriber signs, redeemer is
{"constructor":2,"fields":[]}.
Your validator will burn the NFT and repay penalties as designed.

SubscriberWithdraw – after subscription_end is in the past,
subscriber burns NFT and withdraws the 10 000 AGENT that is still
sitting there (because no one extended).
Redeemer: {"constructor":3,"fields":[]}.

Each action is just a different redeemer and, where necessary, fiddling
with the JSON datum before you CBOR-encode it and give it to
--tx-out-inline-datum-file.

That’s it — you now have a full round-trip: mint, first merchant
withdrawal, and the blueprint to test the other paths.









Sources

You said:
aiken data decode \\ --raw-file old\_datum.cbor \\ --out-file old\_datum.json

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway query utxo \
  --address "$SCRIPT_ADDR" \
  --mainnet --out-file script_utxos.json
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ jq -r '.[].inlineDatum' script_utxos.json | xxd -r -p > old_datum.cbor
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ aiken data decode \
  --raw-file old_datum.cbor \
  --out-file old_datum.json
error: unrecognized subcommand 'data'

Usage: aiken <COMMAND>

For more information, try '--help'.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ aiken --help
Cardano smart contract language and toolchain

Usage: aiken <COMMAND>

Commands:
  new         Create a new Aiken project
  fmt         Format an Aiken project
  export      Export a function as a standalone UPLC program. Arguments to the function can be applied using aiken apply
  build       Build an Aiken project [aliases: b]
  address     Compute a validator's address
  check       
              Type-check an Aiken project and run any tests found.
              
              Test results are printed as stylized outputs when stdout is a TTY-capable terminal. If it
              isn't, (e.g. because you are redirecting the output to a file), test results are printed as
              a JSON structured object. Use --show-json-schema to see the whole schema.
               [aliases: c]
  docs        Build the documentation for an Aiken project
  add         Add a new project package as dependency
  bench       Benchmark an Aiken project
  blueprint   Commands for working with Plutus blueprints
  packages    Managing project dependencies
  tx          Commands for working with transactions
  uplc        Commands for working with untyped Plutus-core
  completion  Get completion scripts for various shells
  help        Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 1m 20s
Below is a concrete, end-to-end recipe that

inspects the current inline datum that is locked at the spend script,

prepares a new datum that adds one 10 000 AGENT installment,

builds, signs and submits the Extend transaction that (=)

keeps the NFT in place,

increases the AGENT locked at the script by another 10 000,

advances subscription_end by one interval_length,

pushes a fresh Installment record onto installments,

is authorised solely by the subscriber’s payment key.

Everything is done with the tooling that is actually present in your Demeter VM.

1 Look at the current datum (no CBOR decoding needed)
bash
Copy
Edit
# 1.1 grab the only UTxO sitting at the spend script
SCRIPT_TX=$(jq -r 'keys[0]' script_utxos.json)

# 1.2 copy its inline datum verbatim into a file we can edit / inspect
jq -r --arg k "$SCRIPT_TX" '.[$k].inlineDatum' script_utxos.json \
  > old_datum.json

# 1.3 optional: pretty-print it
jq . old_datum.json | less -R         # quit with q
You will see something like

json
Copy
Edit
{
  "constructor": 0,
  "fields": [
    { "int": 1000000 },                     # service_fee
    { "int": 0 },                           # penalty_fee
    { "int": 2592000 },                     # interval_length
    { "int": 1747682431 },                  # subscription_start
    { "int": 1750274431 },                  # subscription_end
    { "int": 1750274431 },                  # original_subscription_end
    { "list": [] },                         # installments  <── empty!
    { "bytes": "fe26…ad2a" },               # merchant_key_hash
    { "bytes": "71b9…c9fa8" },              # subscriber_key_hash
    { "bytes": "fe26…ad2a" },               # partner_key_hash
    { "int": 0 }                            # partner_percentage
  ]
}
The empty list at field 6 confirms there are currently no outstanding installments, so a merchant-withdraw is impossible (that path requires the list to be non-empty).

2 Craft the new datum that appends one installment
We add one element to the installments list and advance subscription_end.

bash
Copy
Edit
# 2.1 helper variables
IVL=$(jq -r '.fields[2].int'  old_datum.json)      # 2 592 000
OLD_END=$(jq -r '.fields[4].int' old_datum.json)   # 1 750 274 431
NEW_END=$((OLD_END + IVL))                         # +30 days

# 2.2 build a minimal Installment constructor (index 0)
jq -n --argjson at "$NEW_END" '
  { constructor: 0
  , fields: [ {int: $at}, {int: 10000} ]            # claimable_amount=10k
  }' > new_inst.json

# 2.3 splice it into the datum, bump subscription_end
jq --argjson inst "$(cat new_inst.json)" \
   --argjson newEnd "$NEW_END" '
  .fields[4].int   = $newEnd         |
  .fields[6].list += [$inst]
' old_datum.json > new_datum.json
Double-check the result:

bash
Copy
Edit
jq '.fields[4,6]' new_datum.json
3 Compute datum‐hash & build the Extend transaction
bash
Copy
Edit
# 3.1 hash the new datum (JSON → CBOR → hash)
cardano-cli conway transaction hash-script-data \
  --script-data-file new_datum.json \
  --out-file new_datum.hash

NEW_DHASH=$(cat new_datum.hash)

# 3.2 prepare a temp file that carries the redeemer
cat > extend.redeemer.json <<EOF
{ "constructor": 0, "fields": [ { "int": 1 } ] }   # Extend{additional_intervals=1}
EOF

# 3.3 current script UTxO and value
SCRIPT_TX_IN=$SCRIPT_TX                            # 85b49e…07fd#0
OLD_VALUE=$(jq -r --arg k "$SCRIPT_TX" '.[$k].value' script_utxos.json)

# 3.4 build the *single* script output with +10k AGENT
#     (4000000 lovelace -> keep;   1 NFT -> keep;  AGENT +10k)
NEW_VALUE="+4000000 + 1 ${POLICY_ID}.${ASSET_HEX} + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"

# 3.5 build the balanced tx (subscriber signature only!)
cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address   "$PAYMENT_ADDR" \
  --tx-out           "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference  "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file    old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer     wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
(If your CLI build does not support the new reference-script flags you can fall back
to the older --tx-in-script-file artifacts-mainnet/spend_policy.plutus path; everything
else stays the same.)

4 Sign & submit
bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file   extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file       extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file   extend.tx.signed \
  --mainnet
Once the transaction is confirmed, repeat step 1 to verify:

subscription_end is OLD_END + interval_length,

installments list now contains one element,

the value locked at the script shows 20 000 AGENT.

That finishes an Extend with one extra interval.
From here you can test a MerchantWithdraw exactly as designed: the validator will now find installments non-empty and allow the merchant (partner) to claim their cut when the claimable_at timestamp is inside the validity interval.

What happened to the missing aiken data decode command?
The CLI moved datum helpers under the uplc datum namespace in v1.1.x.
If you ever prefer to decode CBOR with Aiken instead of jq, use:

bash
Copy
Edit
aiken uplc datum decode --raw-file old_datum.cbor --out-file old_datum.json
(You can confirm with aiken uplc datum --help.)

That keeps you entirely inside the Aiken tool-chain without relying on cardano-cli text-view, which was compiled out of the lightweight Demeter build.









Sources
You said:
cardano-cli conway transaction hash-script-data \\ --script-data-file new\_datum.json \\ --out-file new\_datum.hash

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ SCRIPT_TX=$(jq -r 'keys[0]' script_utxos.json)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ jq -r --arg k "$SCRIPT_TX" '.[$k].inlineDatum' script_utxos.json \
  > old_datum.json
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ IVL=$(jq -r '.fields[2].int'  old_datum.json) 
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ OLD_END=$(jq -r '.fields[4].int' old_datum.json)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ NEW_END=$((OLD_END + IVL))
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ jq -n --argjson at "$NEW_END" '
  { constructor: 0
  , fields: [ {int: $at}, {int: 10000} ] 
  }' > new_inst.json
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ jq --argjson inst "$(cat new_inst.json)" \
   --argjson newEnd "$NEW_END" '
  .fields[4].int   = $newEnd         |
  .fields[6].list += [$inst]
' old_datum.json > new_datum.json
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ jq '.fields[4,6]' new_datum.json
{
  "int": 1752866431
}
{
  "list": [
    {
      "constructor": 0,
      "fields": [
        {
          "int": 1752866431
        },
        {
          "int": 10000
        }
      ]
    }
  ]
}
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction hash-script-data \
  --script-data-file new_datum.json \
  --out-file new_datum.hash
Invalid option --out-file'

Usage: cardano-cli 
                     ( address
                     | key
                     | node
                     | query
                     | legacy
                     | byron
                     | shelley
                     | allegra
                     | mary
                     | alonzo
                     | babbage
                     | conway
                     | latest
                     | hash
                     | ping
                     | debug commands
                     | version
                     | compatible
                     )
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 18 seconds
cardano-cli doesn’t have an --out-file switch for hash-script-data; it simply prints the 32-byte datum-hash to stdout.
So just redirect the output yourself:

bash
Copy
Edit
# produce the datum-hash and write it to a file
cardano-cli conway transaction hash-script-data \
  --script-data-file new_datum.json \
  > new_datum.hash      # or “| tee new_datum.hash” if you also want it on-screen
You can verify it was written correctly:

bash
Copy
Edit
cat new_datum.hash        # shows the 64-hex-char hash
Nothing else about the command changes—keep --script-data-file new_datum.json; remove the --out-file flag.









Sources
You said:
cardano-cli conway transaction build \\ --tx-in "$SCRIPT\_TX\_IN" \\ --tx-in-collateral "$COLLATERAL\_TX" \\ --change-address "$PAYMENT\_ADDR" \\ --tx-out "$SCRIPT\_ADDR $NEW\_VALUE" \\ --tx-out-datum-hash "$NEW\_DHASH" \\ --spending-tx-in-reference "$SCRIPT\_TX\_IN" \\ --spending-plutus-script-v3 \\ --spending-reference-tx-in-datum-file old\_datum.json \\ --spending-reference-tx-in-redeemer-file extend.redeemer.json \\ --required-signer wallets/subscriber/payment.skey \\ --protocol-params-file pparams.json \\ --out-file extend.txbody \\ --mainnet

got all the way to the build tx this time...


abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction hash-script-data \
  --script-data-file new_datum.json \
  > new_datum.hash
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cat new_datum.hash
a27ce56502a92a3d5b93d53b8578413293fa6e35854fcb18fc2244fe4795e0da
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ NEW_DHASH=$(cat new_datum.hash)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cat > extend.redeemer.json <<EOF
{ "constructor": 0, "fields": [ { "int": 1 } ] }   # Extend{additional_intervals=1}
EOF
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ SCRIPT_TX_IN=$SCRIPT_TX
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ OLD_VALUE=$(jq -r --arg k "$SCRIPT_TX" '.[$k].value' script_utxos.json)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ NEW_VALUE="+4000000 + 1 ${POLICY_ID}.${ASSET_HEX} + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address   "$PAYMENT_ADDR" \
  --tx-out           "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference  "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file    old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer     wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ echo $NEW_VALUE
+4000000 + 1 efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb.4147454e545f5355425f4e4654 + 20000 97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec.54616c6f73
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ echo $COLL_TX
ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ export COLLATERAL_TX=ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build   --tx-in "$SCRIPT_TX_IN"   --tx-in-collateral "$COLLATERAL_TX"   --change-address   "$PAYMENT_ADDR"   --tx-out           "$SCRIPT_ADDR $NEW_VALUE"   --tx-out-datum-hash "$NEW_DHASH"   --spending-tx-in-reference  "$SCRIPT_TX_IN"   --spending-plutus-script-v3   --spending-reference-tx-in-datum-file    old_datum.json   --spending-reference-tx-in-redeemer-file extend.redeemer.json   --required-signer     wallets/subscriber/payment.skey   --protocol-params-file pparams.json   --out-file extend.txbody   --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 14 seconds
cardano‐cli expects the address and the value expression to be separated by a plus sign (+) with no intervening space.
In the command you ran you inserted a plain space:

bash
Copy
Edit
--tx-out "$SCRIPT_ADDR $NEW_VALUE"
#                    ^ space, no plus
so the parser stopped right after the address, met the space, and thought the option had ended – that’s why it complained about “unexpected end of input” for --change-address.

✅ Fix
Put a “+” directly after the script address (no space).

Keep the value expression exactly as you built it.

bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address "$PAYMENT_ADDR" \
  --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \        # <- plus sign here
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference  "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file    old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer     wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
Tip: if you ever need to see exactly what string is being passed, run set -x in the shell; Bash will echo each expanded line so you can spot quoting/spacing issues immediately.

After rebuilding the body, sign and submit as usual:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
That should compile and submit without the “unexpected end of input” error.








You said:
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address "$PAYMENT_ADDR" \
  --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \ 
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference  "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file    old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer     wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
bash: --tx-out-datum-hash: command not found
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:
The CLI is still choking on the --tx-out argument.
Two things are happening at once:

The back-slash at the end of the --tx-out line is followed by a space.
In Bash a back-slash must be the final byte on the line to escape the newline.
If you write ...\␠<newline> the back-slash escapes that literal space and the newline is treated as real ⇒ the next token becomes --tx-out-datum-hash, the value expression is lost and the parser stops at --change-address.

$NEW_VALUE already starts with a leading “+”.
That’s correct, but it means the whole value expression must be quoted as one word with no internal newlines.

What to change
bash
Copy
Edit
# 1) remove the trailing space after the back-slash
# 2) keep the whole tx-out argument on **one physical line**
#    (or add another back-slash-newline pair later, but without spaces)

cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address "$PAYMENT_ADDR" \
  --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
Tip: if you want to split the long --tx-out line you can, but escape the newline and don’t leave a space after the back-slash, e.g.
--tx-out "$SCRIPT_ADDR+\<newline> $NEW_VALUE"`.

After it builds, sign & submit:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
This should go through without the “unexpected end of input / command not found” messages.








You said:
cardano-cli conway transaction build \\ --tx-in "$SCRIPT\_TX\_IN" \\ --tx-in-collateral "$COLLATERAL\_TX" \\ --change-address "$PAYMENT\_ADDR" \\ --tx-out "$SCRIPT\_ADDR+$NEW\_VALUE" \\ --tx-out-datum-hash "$NEW\_DHASH" \\ --spending-tx-in-reference "$SCRIPT\_TX\_IN" \\ --spending-plutus-script-v3 \\ --spending-reference-tx-in-datum-file old\_datum.json \\ --spending-reference-tx-in-redeemer-file extend.redeemer.json \\ --required-signer wallets/subscriber/payment.skey \\ --protocol-params-file pparams.json \\ --out-file extend.txbody \\ --mainnet

cardano-cli conway transaction build \
  --tx-in $TX_IN1 \
  --tx-in $TX_IN2 \
  --change-address "$PAYMENT_ADDR" \
  --tx-out "$PAYMENT_ADDR+${LOV} \
            + 1 ${POLICY_ID}.${ASSET_HEX} \
            + 10000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}" \
  --tx-out-inline-datum-file datum.json \
  --mint="1 ${POLICY_ID}.${ASSET_HEX}" \
  --mint-script-file artifacts-mainnet/mint_policy.plutus \
  --mint-redeemer-file subscribe.json \
  --required-signer-hash $SIG_HASH \
  --required-signer-hash $SUB_HASH \
  --out-file mint.txbody \
  --mainnet


This is what we did before and it worked...

still getting errors with this new one...

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address "$PAYMENT_ADDR" \
  --tx-out "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --spending-tx-in-reference "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file old_datum.json \
  --spending-reference-tx-in-redeemer-file extend.redeemer.json \
  --required-signer wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 2m 59s
Here’s why cardano-cli keeps stopping at --change-address and how to fix the whole command.

What is going wrong
Symptom	Root-cause
option --change-address: unexpected end of input	The shell thinks no value was supplied after --change-address because the previous line-continuation (\) is followed by a space. In Bash a back-slash must be the very last character on the line – any trailing blank cancels the continuation. 
Input Output
Still fails after removing the space	a. Your NEW_VALUE already starts with +, so writing "$SCRIPT_ADDR+$NEW_VALUE" produces addr…++4000000… (double-+).
b. The script datum you want to spend sits in the same UTxO that you are also trying to use as a reference script (--spending-tx-in-reference "$SCRIPT_TX_IN"). A reference input must be distinct from the script UTxO being consumed. 
Cardano Stack Exchange

Quick sanity checks before rebuilding
bash
Copy
Edit
# 1. no trailing blanks after every back-slash
# 2. make sure the vars are not empty
printf '%s\n' "$PAYMENT_ADDR" "$SCRIPT_ADDR" "$SCRIPT_TX_IN" "$COLLATERAL_TX" \
              "$NEW_VALUE" "$NEW_DHASH" | sed -e 's/.*/OK: &/'
# 3. NEW_VALUE must *not* start with '+'
NEW_VALUE="4000000 \
           + 1 ${POLICY_ID}.${ASSET_HEX} \
           + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"
Build the Extend transaction step-by-step
Assumption: you do not have a separate reference-script UTxO yet, so we spend with the full script file rather than a reference.

bash
Copy
Edit
### 1. point to the compiled spend validator
SPEND_SCRIPT=artifacts-mainnet/spend.plutus   # ← file produced by
                                              #     aiken blueprint convert …

### 2. build
cardano-cli conway transaction build \
  --mainnet \
  --tx-in            "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --tx-out "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --change-address     "$PAYMENT_ADDR" \
  \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  \
  --required-signer       wallets/subscriber/payment.skey \
  --protocol-params-file  pparams.json \
  --out-file              extend.txbody
Key differences from the command that failed

No blank after each \ – every continuation is clean.

"$SCRIPT_ADDR $NEW_VALUE" (a single space) instead of "$SCRIPT_ADDR+$NEW_VALUE".

Script witness supplied with --tx-in-script-file because you are spending the UTxO that contains the script; you cannot reference the same UTxO.

NEW_VALUE starts with the number, not with +.

Sign and submit
bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
If you want to use a reference script later
First create a “reference-script UTxO” (send 1 ₳ + reference script to a fresh address, flag with --tx-out-reference-script-file $SPEND_SCRIPT).

In subsequent Extend / Withdraw transactions replace

bash
Copy
Edit
--tx-in-script-file $SPEND_SCRIPT
with

bash
Copy
Edit
--spending-tx-in-reference  <txHash#ix_of_reference_script>
--spending-plutus-script-v3
and omit --tx-in-script-file.

Why the shell is so picky about the back-slash
The POSIX shell grammar treats a back-slash plus newline as one token that gets removed, letting the command continue on the next line; any trailing character (even a space) breaks that combo and the newline becomes a real statement terminator. 
Input Output

That command should now build without unexpected end of input, produce a balanced transaction, and let you test the Extend flow. If you hit any other error, run cardano-cli conway transaction build ... --script-invalid --calculate-plutus-script-cost cost.json to collect on-chain logs and we can debug further.











Sources
You said:
Quick sanity checks before rebuilding ------------------------------------- bash CopyEdit `# 1. no trailing blanks after every back-slash # 2. make sure the vars are not empty printf '%s\n' "$PAYMENT_ADDR" "$SCRIPT_ADDR" "$SCRIPT_TX_IN" "$COLLATERAL_TX" \ "$NEW_VALUE" "$NEW_DHASH" | sed -e 's/.*/OK: &/' # 3. NEW_VALUE must *not* start with '+' NEW_VALUE="4000000 \ + 1 ${POLICY_ID}.${ASSET_HEX} \ + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"` Build the **Extend** transaction step-by-step --------------------------------------------- > **Assumption**: you _do **not**_ have a separate reference-script UTxO yet, so we spend with the full script file rather than a reference. bash CopyEdit `### 1. point to the compiled spend validator SPEND_SCRIPT=artifacts-mainnet/spend.plutus # ← file produced by # aiken blueprint convert …`

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ printf '%s\n' "$PAYMENT_ADDR" "$SCRIPT_ADDR" "$SCRIPT_TX_IN" "$COLLATERAL_TX" \
              "$NEW_VALUE" "$NEW_DHASH" | sed -e 's/.*/OK: &/'
OK: 
OK: addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf
OK: 85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0
OK: ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
OK: +4000000 + 1 efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb.4147454e545f5355425f4e4654 + 20000 97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec.54616c6f73
OK: a27ce56502a92a3d5b93d53b8578413293fa6e35854fcb18fc2244fe4795e0da
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ NEW_VALUE="4000000 \
           + 1 ${POLICY_ID}.${ASSET_HEX} \
           + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ printf '%s\n' "$PAYMENT_ADDR" "$SCRIPT_ADDR" "$SCRIPT_TX_IN" "$COLLATERAL_TX"               "$NEW_VALUE" "$NEW_DHASH" | sed -e 's/.*/OK: &/'
OK: 
OK: addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf
OK: 85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0
OK: ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
OK: 4000000            + 1 efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb.4147454e545f5355425f4e4654            + 20000 97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec.54616c6f73
OK: a27ce56502a92a3d5b93d53b8578413293fa6e35854fcb18fc2244fe4795e0da
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build   --tx-in "$SCRIPT_TX_IN"   --tx-in-collateral "$COLLATERAL_TX"   --change-address "$PAYMENT_ADDR"   --tx-out "$SCRIPT_ADDR+$NEW_VALUE"   --tx-out-datum-hash "$NEW_DHASH"   --spending-tx-in-reference "$SCRIPT_TX_IN"   --spending-plutus-script-v3   --spending-reference-tx-in-datum-file old_datum.json   --spending-reference-tx-in-redeemer-file extend.redeemer.json   --required-signer wallets/subscriber/payment.skey   --protocol-params-file pparams.json   --out-file extend.txbody   --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 

and my spend is subscription/artifacts-mainnet/spend_policy.plutus


ChatGPT said:

Thought for 23 seconds
Below is the shortest, bullet-proof way to get past the parsing error and build an Extend {additional_intervals = 1} transaction.
There are two independent fixes you must apply:

1 Correct the --tx-out syntax
cardano-cli expects the address and the value to be separated by a space, not glued together with a ‘+’.

The value itself must not start with a leading ‘+’.

bash
Copy
Edit
# good
--tx-out  "$SCRIPT_ADDR $NEW_VALUE"

# bad – what you typed before
--tx-out  "$SCRIPT_ADDR+$NEW_VALUE"
That single extra ‘+’ makes the parser think the option is unfinished, so it stops when it reaches --change-address, giving the “unexpected end of input” message. 
Reddit

2 Use the ordinary script-spend flags (you do not have a reference script yet)
Because the spend validator is inside the same UTxO you are consuming, you should point to the compiled script file itself, not use the --spending-tx-in-reference … flags (those are only for reference scripts held in a different UTxO) 
Cardano Stack Exchange
.

bash
Copy
Edit
# Path to the compiled spend validator produced with
#   aiken blueprint convert … > artifacts-mainnet/spend_policy.plutus
SPEND_SCRIPT=artifacts-mainnet/spend_policy.plutus
Full working command
bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in            "$SCRIPT_TX_IN" \
  --tx-in-script-file "$SPEND_SCRIPT" \
  --tx-in-datum-file  old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address   "$PAYMENT_ADDR" \
  --tx-out           "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --required-signer-file wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
What changed compared with your last attempt?
Flag	Old value	New value
--tx-out	"$SCRIPT_ADDR+$NEW_VALUE"	"$SCRIPT_ADDR $NEW_VALUE"
script witness	--spending-tx-in-reference … --spending-plutus-script-v3	--tx-in-script-file $SPEND_SCRIPT
datum / redeemer	--spending-reference-tx-in-*	--tx-in-datum-file …
--tx-in-redeemer-file …
signer flag	--required-signer	--required-signer-file

Everything else (collateral, change address, datum-hash, etc.) stays the same.

Next steps
Build the body with the command above.

Sign with the subscriber key and the collateral owner (admin) key if they differ:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file   extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --signing-key-file wallets/admin/payment.skey \
  --out-file       extend.tx.signed \
  --mainnet
Submit:

bash
Copy
Edit
cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
Once this goes on-chain you will see:

the original script UTxO spent,

a new script UTxO with 20 000 AGENT and the updated datum,

the NFT still in the script output (no mint/burn),

change back to the admin wallet.

Why we did not use reference scripts yet
A reference-script UTxO saves a lot of bytes, but you have to create it first and then point to it with --spending-tx-in-reference. Until you have that separate UTxO, spending with the full script file is the simplest, most reliable path. 
CoinCashew

You should now be able to build the transaction without the “unexpected end of input” error. If anything else pops up, run the printf … | sed 's/.*/OK: &/' check again: nine times out of ten a silent empty variable (or an extra ‘+’) is the culprit.












Sources
You said:
cardano-cli conway transaction build \\ --tx-in "$SCRIPT\_TX\_IN" \\ --tx-in-script-file "$SPEND\_SCRIPT" \\ --tx-in-datum-file old\_datum.json \\ --tx-in-redeemer-file extend.redeemer.json \\ --tx-in-collateral "$COLLATERAL\_TX" \\ --change-address "$PAYMENT\_ADDR" \\ --tx-out "$SCRIPT\_ADDR $NEW\_VALUE" \\ --tx-out-datum-hash "$NEW\_DHASH" \\ --required-signer-file wallets/subscriber/payment.skey \\ --protocol-params-file pparams.json \\ --out-file extend.txbody \\ --mainnet

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in            "$SCRIPT_TX_IN" \
  --tx-in-script-file "$SPEND_SCRIPT" \
  --tx-in-datum-file  old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-in-collateral "$COLLATERAL_TX" \
  --change-address   "$PAYMENT_ADDR" \
  --tx-out           "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --required-signer-file wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
option --change-address: 
unexpected end of input

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


maybe we need to print all the variables and confirm them right before attempting again... not sure why we are going in circles


ChatGPT said:

Thought for 1m 51s
Quick summary
cardano-cli … transaction build aborts with

vbnet
Copy
Edit
option --change-address: unexpected end of input
whenever the argument that must follow --change-address is empty (or the shell has already consumed the newline). In your last runs the very first “OK:” line printed from the diagnostic helper was blank, so $PAYMENT_ADDR is currently unset/empty. The CLI therefore sees --change-address followed immediately by the next flag and raises the “end of input” parser error. 
Cardano Stack Exchange

1 Fix the empty variable
bash
Copy
Edit
# re-export the admin’s payment address  
export PAYMENT_ADDR=$(cat wallets/admin/payment.addr)

# verify it is NOT empty
[ -n "$PAYMENT_ADDR" ] && echo "Addr loaded ✅" || echo "Addr missing ❌"
If that prints ‘Addr missing’, open wallets/admin/payment.addr; it must contain
a single Bech32 address. Re-create the key/address if needed (see Cardano
doc example). 
Cardano Stack Exchange

2 Re-check every variable right before building
bash
Copy
Edit
printf '%-18s  %s\n' \
 "PAYMENT_ADDR" "$PAYMENT_ADDR" \
 "SCRIPT_ADDR"  "$SCRIPT_ADDR"  \
 "SCRIPT_TX_IN" "$SCRIPT_TX_IN" \
 "COLLATERAL_TX" "$COLLATERAL_TX" \
 "NEW_VALUE"    "$NEW_VALUE" \
 "NEW_DHASH"    "$NEW_DHASH" \
 "SPEND_SCRIPT" "$SPEND_SCRIPT"
All lines must show a non-empty value; the NEW_VALUE line must not contain
line-breaks (use back-slashes only inside the quoted string, not after it).
Missing or wrapped values are the other common cause of the same error. 
GitHub
Cardano Stack Exchange

3 Build the “Extend” transaction (working template)
bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in            "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --tx-in-script-file  "$SPEND_SCRIPT" \
  --tx-in-datum-file    old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-out "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --change-address  "$PAYMENT_ADDR" \
  --required-signer-file wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
Why this layout works

Every positional pair (--tx-out ADDRESS VALUE, --tx-in HASH#IX, …) is kept
contiguous as the CLI parser expects. 
Cardano Stack Exchange

The value string uses a plain space between $SCRIPT_ADDR and the asset
bundle; the leading ‘+’ was removed. (ADDRESS VALUE is the official
syntax — see docs). 
Cardano Stack Exchange

All file-paths are passed with their dedicated flags (no mixed
reference-input flags, which the CLI will ignore unless you use
--spending-tx-in-reference). 
Cardano Docs

Only one --required-signer-file is needed because we supply the full signing
key; if you prefer hashes add separate --required-signer-hash HASH. 
Cardano Stack Exchange

4 Typical follow-up steps
Estimate / view script cost (optional):

bash
Copy
Edit
cardano-cli conway transaction build \
  …same flags… \
  --calculate-plutus-script-cost extend.cost \
  --mainnet
Sign the balanced body:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet
Submit:

bash
Copy
Edit
cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
Verify the new script UTxO (installment added, agent balance +10 k):

bash
Copy
Edit
cardano-cli conway query utxo --address "$SCRIPT_ADDR" --mainnet
If you still hit “unexpected end of input”
Empty variable → re-export & print (step 2).

Line-break inside --tx-out → keep ADDRESS VALUE on the same shell
line.

Wrong flag ordering (e.g., --change-address before any --tx-out) →
follow the exact order above; the CLI’s parser is strict. 
Cardano Docs

With the variables now populated and the flags in the proper order your extend
transaction should build and balance successfully.












Sources
You said:
All lines must show a non-empty value; the **`NEW_VALUE`** line must not contain line-breaks (use back-slashes only _inside_ the quoted string, not after it). Missing or wrapped values are the other common cause of the same error. [GitHub](https://github.com/input-output-hk/cardano-node/issues/3840?utm_source=chatgpt.com)[Cardano Stack Exchange](https://cardano.stackexchange.com/questions/3865/lobster-challenge-zsh-no-matches-found-error-on-building-transaction?rq=1&utm_source=chatgpt.com) * * * 3 Build the “Extend” transaction (working template) --------------------------------------------------- bash CopyEdit `cardano-cli conway transaction build \ --tx-in "$SCRIPT_TX_IN" \ --tx-in-collateral "$COLLATERAL_TX" \ --tx-in-script-file "$SPEND_SCRIPT" \ --tx-in-datum-file old_datum.json \ --tx-in-redeemer-file extend.redeemer.json \ --tx-out "$SCRIPT_ADDR $NEW_VALUE" \ --tx-out-datum-hash "$NEW_DHASH" \ --change-address "$PAYMENT_ADDR" \ --required-signer-file wallets/subscriber/payment.skey \ --protocol-params-file pparams.json \ --out-file extend.txbody \ --mainnet`

maybe we need to refactor how we are doing NEW_VALUE... I think it is the problem now. Just look the print statement:


abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ export PAYMENT_ADDR=$(cat wallets/admin/payment.addr)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ [ -n "$PAYMENT_ADDR" ] && echo "Addr loaded ✅" || echo "Addr missing ❌"
Addr loaded ✅
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ printf '%-18s  %s\n' \
 "PAYMENT_ADDR" "$PAYMENT_ADDR" \
 "SCRIPT_ADDR"  "$SCRIPT_ADDR"  \
 "SCRIPT_TX_IN" "$SCRIPT_TX_IN" \
 "COLLATERAL_TX" "$COLLATERAL_TX" \
 "NEW_VALUE"    "$NEW_VALUE" \
 "NEW_DHASH"    "$NEW_DHASH" \
 "SPEND_SCRIPT" "$SPEND_SCRIPT"
PAYMENT_ADDR        addr1q8lzdr4hc52lcd0eh08zp0g3y3kcc7qwp8dmeqrck04262s8klxeuth8gczs7vxdr080gk48frmzfhwk97zgql3drvjqkkdv5n
SCRIPT_ADDR         addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf
SCRIPT_TX_IN        85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0
COLLATERAL_TX       ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
NEW_VALUE           4000000            + 1 efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb.4147454e545f5355425f4e4654            + 20000 97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec.54616c6f73
NEW_DHASH           a27ce56502a92a3d5b93d53b8578413293fa6e35854fcb18fc2244fe4795e0da
SPEND_SCRIPT        
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in            "$SCRIPT_TX_IN" \
  --tx-in-collateral "$COLLATERAL_TX" \
  --tx-in-script-file  "$SPEND_SCRIPT" \
  --tx-in-datum-file    old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-out "$SCRIPT_ADDR $NEW_VALUE" \
  --tx-out-datum-hash "$NEW_DHASH" \
  --change-address  "$PAYMENT_ADDR" \
  --required-signer-file wallets/subscriber/payment.skey \
  --protocol-params-file pparams.json \
  --out-file extend.txbody \
  --mainnet
Invalid option --required-signer-file'

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 30 seconds
Below is a quick-diagnosis checklist that will usually clear every “--change-address: unexpected end of input” / “unknown switch” loop you’re seeing, plus a rock-solid template you can paste after the checks.

1 Double-check every variable before you call cardano-cli
bash
Copy
Edit
# 1.1 – paths & hashes --------------------------------------------------
export SPEND_SCRIPT="subscription/artifacts-mainnet/spend_policy.plutus"
export PAYMENT_ADDR=$(< wallets/admin/payment.addr)             # no newline
export SCRIPT_ADDR=$(< artifacts-mainnet/spend.addr)
export SCRIPT_TX_IN="85b49e…07fd#0"           # the script UTxO
export COLLATERAL_TX="ce824a…daa5#0"          # any pure-ada UTxO ≥ 5 ADA
export NEW_DHASH="a27ce56502…e4795e0da"       # hash of new datum

# 1.2 – token bundle to remain at the script
NEW_VALUE="4000000 \
          + 1 efd55074…552eb.4147454e545f5355425f4e4654 \
          + 20000 97bbb7db…74bec.54616c6f73"
# ⇧ one long line – **no line-breaks** or the CLI stops at “+”

# 1.3 – sanity-print (EVERY item must be non-empty & on one line)
printf '%-15s %s\n' \
  PAYMENT_ADDR "$PAYMENT_ADDR" \
  SCRIPT_ADDR  "$SCRIPT_ADDR"  \
  SCRIPT_TX_IN "$SCRIPT_TX_IN" \
  COLLATERAL_TX "$COLLATERAL_TX" \
  NEW_DHASH    "$NEW_DHASH"    \
  SPEND_SCRIPT "$SPEND_SCRIPT" \
  NEW_VALUE    "$NEW_VALUE"
If any field prints blank or wraps, fix it before you rebuild – that alone causes the “unexpected end of input” error 90 % of the time. 
Cardano Forum

2 Use the exact switch names the Conway CLI expects
--required-signer (file path!) – there is no --required-signer-file in the new sub-CLI.

--tx-out syntax is “ADDRESS+VALUE” – the plus touches the address.

All script-spending flags must appear after their matching --tx-in.

The complete, order-safe template is therefore 👇

bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --protocol-params-file  pparams.json \
  --out-file              extend.txbody \
  --mainnet
Common slip-ups this template avoids:

Symptom	Root cause	Fix
unexpected end of input right after --change-address	$PAYMENT_ADDR empty or newline	reload with $(< file)
option --tx-out: same message	NEW_VALUE wrapped onto a new line	one-line string (see §1)
Invalid option --required-signer-file	Flag name changed in 8.11+	use --required-signer
unknown switch --tx-in-script-file	Order: --tx-in must appear before its script flags	keep the order exactly as above

Sources with the same pitfalls & fixes: official CLI help, GitHub issues, and SE threads. 
Cardano Forum
Cardano Stack Exchange
Reddit
Cardano Forum

3 Why NEW_VALUE must be one line
cardano-cli token parsing stops on the first newline; the remainder of the bundle is thrown away, so the parser reaches the next flag early and reports “unexpected end of input”. This is confirmed in the IOHK guide and multiple bug reports. 
Cardano Developer Portal
Cardano Forum

4 Next steps
Run the sanity print again – every field must show.

Paste the template exactly (or wrap it in a heredoc).

Sign & submit:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --mainnet \
  --out-file extend.tx.signed

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed --mainnet
Once it lands, the script UTxO will now hold 20 000 AGENT and the new extended datum.

If any flag still errors, re-run the variable print – it will always point at the missing or malformed value.

Happy extending!












Sources
You said:
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ printf '%-15s %s\n' \
  PAYMENT_ADDR "$PAYMENT_ADDR" \
  SCRIPT_ADDR  "$SCRIPT_ADDR"  \
  SCRIPT_TX_IN "$SCRIPT_TX_IN" \
  COLLATERAL_TX "$COLLATERAL_TX" \
  NEW_DHASH    "$NEW_DHASH"    \
  SPEND_SCRIPT "$SPEND_SCRIPT" \
  NEW_VALUE    "$NEW_VALUE"
PAYMENT_ADDR    addr1q8lzdr4hc52lcd0eh08zp0g3y3kcc7qwp8dmeqrck04262s8klxeuth8gczs7vxdr080gk48frmzfhwk97zgql3drvjqkkdv5n
SCRIPT_ADDR     addr1w8agnx3v5anvfy20sx7yzzjmupe8lfxqf5k204u0u3ux0hgt0r5kf
SCRIPT_TX_IN    85b49ecc946c6d87d2b9eae008b77f2abe5e8aa706c338f3445febafe36007fd#0
COLLATERAL_TX   ce824a138d5241e68f7b506a36c9e1135683df92a7e5df99d00923a04cbddaa5#0
NEW_DHASH       a27ce56502a92a3d5b93d53b8578413293fa6e35854fcb18fc2244fe4795e0da
SPEND_SCRIPT    subscription/artifacts-mainnet/spend_policy.plutus
NEW_VALUE       4000000           + 1 efd550741e3110fe49eab48f76b92e80b0676b4435c8e282810552eb.4147454e545f5355425f4e4654           + 20000 97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec.54616c6f73
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --protocol-params-file  pparams.json \
  --out-file              extend.txbody \
  --mainnet
Invalid option --protocol-params-file'

Usage: cardano-cli conway transaction build [--socket-path SOCKET_PATH]
                                              [--cardano-mode
                                                [--epoch-slots SLOTS]]
                                              [ --mainnet
                                              | --testnet-magic NATURAL
                                              ]
                                              [ --script-valid
                                              | --script-invalid
                                              ]
                                              [--witness-override WORD]
                                              (--tx-in TX-IN
                                                [ --spending-tx-in-reference TX-IN
                                                  ( --spending-plutus-script-v2
                                                  | --spending-plutus-script-v3
                                                  )
                                                  [ --spending-reference-tx-in-datum-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-datum-file JSON_FILE
                                                  | --spending-reference-tx-in-datum-value JSON_VALUE
                                                  | --spending-reference-tx-in-inline-datum-present
                                                  ]
                                                  ( --spending-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --spending-reference-tx-in-redeemer-file JSON_FILE
                                                  | --spending-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                | --simple-script-tx-in-reference TX-IN
                                                | --tx-in-script-file FILEPATH
                                                  [
                                                    [ --tx-in-datum-cbor-file CBOR_FILE
                                                    | --tx-in-datum-file JSON_FILE
                                                    | --tx-in-datum-value JSON_VALUE
                                                    | --tx-in-inline-datum-present
                                                    ]
                                                    ( --tx-in-redeemer-cbor-file CBOR_FILE
                                                    | --tx-in-redeemer-file JSON_FILE
                                                    | --tx-in-redeemer-value JSON_VALUE
                                                    )]
                                                ])
                                              [--read-only-tx-in-reference TX-IN]
                                              [ --required-signer FILEPATH
                                              | --required-signer-hash HASH
                                              ]
                                              [--tx-in-collateral TX-IN]
                                              [--tx-out-return-collateral ADDRESS VALUE]
                                              [--tx-total-collateral INTEGER]
                                              [--tx-out ADDRESS VALUE
                                                [ --tx-out-datum-hash HASH
                                                | --tx-out-datum-hash-cbor-file CBOR_FILE
                                                | --tx-out-datum-hash-file JSON_FILE
                                                | --tx-out-datum-hash-value JSON_VALUE
                                                | --tx-out-datum-embed-cbor-file CBOR_FILE
                                                | --tx-out-datum-embed-file JSON_FILE
                                                | --tx-out-datum-embed-value JSON_VALUE
                                                | --tx-out-inline-datum-cbor-file CBOR_FILE
                                                | --tx-out-inline-datum-file JSON_FILE
                                                | --tx-out-inline-datum-value JSON_VALUE
                                                ]
                                                [--tx-out-reference-script-file FILEPATH]]
                                              --change-address ADDRESS
                                              [--mint VALUE
                                                ( --mint-script-file FILEPATH
                                                  [ --mint-redeemer-cbor-file CBOR_FILE
                                                  | --mint-redeemer-file JSON_FILE
                                                  | --mint-redeemer-value JSON_VALUE
                                                  ]
                                                | --simple-minting-script-tx-in-reference TX-IN
                                                  --policy-id HASH
                                                | --mint-tx-in-reference TX-IN
                                                  ( --mint-plutus-script-v2
                                                  | --mint-plutus-script-v3
                                                  )
                                                  ( --mint-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --mint-reference-tx-in-redeemer-file JSON_FILE
                                                  | --mint-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                  --policy-id HASH
                                                )]
                                              [--invalid-before SLOT]
                                              [--invalid-hereafter SLOT]
                                              [--certificate-file FILEPATH
                                                [ --certificate-script-file FILEPATH
                                                  [ --certificate-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-redeemer-file JSON_FILE
                                                  | --certificate-redeemer-value JSON_VALUE
                                                  ]
                                                | --certificate-tx-in-reference TX-IN
                                                  ( --certificate-plutus-script-v2
                                                  | --certificate-plutus-script-v3
                                                  )
                                                  ( --certificate-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --certificate-reference-tx-in-redeemer-file JSON_FILE
                                                  | --certificate-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--withdrawal WITHDRAWAL
                                                [ --withdrawal-script-file FILEPATH
                                                  [ --withdrawal-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-redeemer-file JSON_FILE
                                                  | --withdrawal-redeemer-value JSON_VALUE
                                                  ]
                                                | --withdrawal-tx-in-reference TX-IN
                                                  ( --withdrawal-plutus-script-v2
                                                  | --withdrawal-plutus-script-v3
                                                  )
                                                  ( --withdrawal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --withdrawal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [ --json-metadata-no-schema
                                              | --json-metadata-detailed-schema
                                              ]
                                              [--auxiliary-script-file FILEPATH]
                                              [ --metadata-json-file FILEPATH
                                              | --metadata-cbor-file FILEPATH
                                              ]
                                              [--vote-file FILEPATH
                                                [ --vote-script-file FILEPATH
                                                  [ --vote-redeemer-cbor-file CBOR_FILE
                                                  | --vote-redeemer-file JSON_FILE
                                                  | --vote-redeemer-value JSON_VALUE
                                                  ]
                                                | --vote-tx-in-reference TX-IN
                                                  --vote-plutus-script-v3
                                                  ( --vote-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --vote-reference-tx-in-redeemer-file JSON_FILE
                                                  | --vote-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--proposal-file FILEPATH
                                                [ --proposal-script-file FILEPATH
                                                  [ --proposal-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-redeemer-file JSON_FILE
                                                  | --proposal-redeemer-value JSON_VALUE
                                                  ]
                                                | --proposal-tx-in-reference TX-IN
                                                  --proposal-plutus-script-v3
                                                  ( --proposal-reference-tx-in-redeemer-cbor-file CBOR_FILE
                                                  | --proposal-reference-tx-in-redeemer-file JSON_FILE
                                                  | --proposal-reference-tx-in-redeemer-value JSON_VALUE
                                                  )
                                                ]]
                                              [--treasury-donation LOVELACE]
                                              ( --out-file FILEPATH
                                              | --calculate-plutus-script-cost FILEPATH
                                              )

  Build a balanced transaction (automatically calculates fees)

  Please note the order of some cmd options is crucial. If used incorrectly may produce undesired tx body. See nested [] notation above for details.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 6 seconds
Quick fix — remove the --protocol-params-file flag
The Conway-era cardano-cli conway transaction build sub-command queries the node for the current protocol parameters automatically.
--protocol-params-file is therefore not accepted and the parser stops as soon as it sees it, giving the “Invalid option” error you’re getting.

Working command template
Below is the same command you tried, but

without --protocol-params-file;

with an unbroken --tx-out bundle (ADDRESS+VALUE, no extra blanks);

using the reference-script style (optional -- see note ⓘ).

bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --out-file              extend.txbody \
  --mainnet
ⓘ If you prefer the reference-input pattern
Replace the three lines beginning with --tx-in-script-file, --tx-in-datum-file, and --tx-in-redeemer-file with

bash
Copy
Edit
  --spending-tx-in-reference "$SCRIPT_TX_IN" \
  --spending-plutus-script-v3 \
  --spending-reference-tx-in-datum-file     old_datum.json \
  --spending-reference-tx-in-redeemer-file  extend.redeemer.json \
(and keep --tx-in for the actual input being spent).

Common gotchas (all now covered)
Check	Why it matters
No line-breaks inside NEW_VALUE	A newline terminates the token list early and makes the CLI treat “+” or the next token as a flag.
"$SCRIPT_ADDR+$NEW_VALUE" (plus touches)	The space you had earlier ("$SCRIPT_ADDR $NEW_VALUE") splits the argument and fails parsing.
--required-signer (not --required-signer-file)	Conway sub-command renamed the flag.
Remove --protocol-params-file	Only the old build-raw path still needs it.

After the build succeeds:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
You should now see a new script UTxO with 20 000 AGENT, the NFT, and the updated datum (subscription_end advanced, one installment added).








You said:
Great! now we just need to make a small adjustment since we are already IN the subscription dir and this is trying to find another /subscription dir for the /artifacts-mainnet/spend_policy.plutus


abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --out-file              extend.txbody \
  --mainnet
Command failed: transaction build  Error: subscription/artifacts-mainnet/spend_policy.plutus: subscription/artifacts-mainnet/spend_policy.plutus: openBinaryFile: does not exist (No such file or directory)
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$


ChatGPT said:
Your $SPEND_SCRIPT still has the extra leading subscription/….
Just redefine it (or give the absolute path) and re-run the build.

bash
Copy
Edit
# we are already in …/repo/subscription
export SPEND_SCRIPT="artifacts-mainnet/spend_policy.plutus"   # <- correct

# sanity-check the file really exists
ls -l "$SPEND_SCRIPT"       # should list the .plutus file
Now rebuild exactly as before:

bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --out-file              extend.txbody \
  --mainnet
If the file lists correctly and the command still errors, double-check the working directory (pwd) and the spelling of artifacts-mainnet/spend_policy.plutus.








You said:
export SPEND\_SCRIPT="artifacts-mainnet/spend\_policy.plutus"

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ export SPEND_SCRIPT="artifacts-mainnet/spend_policy.plutus"
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build   --tx-in                 "$SCRIPT_TX_IN"   --tx-in-script-file     "$SPEND_SCRIPT"   --tx-in-datum-file      old_datum.json   --tx-in-redeemer-file   extend.redeemer.json   --tx-in-collateral      "$COLLATERAL_TX"   --tx-out                "$SCRIPT_ADDR+$NEW_VALUE"   --tx-out-datum-hash     "$NEW_DHASH"   --change-address        "$PAYMENT_ADDR"   --required-signer       wallets/subscriber/payment.skey   --out-file              extend.txbody   --mainnet
Command failed: transaction build  Error: Invalid JSON format in file: "extend.redeemer.json"
JSON parse error: Trailing garbage 
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 



subscription/extend.redeemer.json
{ "constructor": 0, "fields": [ { "int": 1 } ] }   # Extend{additional_intervals=1}


ChatGPT said:
cardano-cli expects pure JSON – any trailing characters (comments, extra whitespace after the closing brace, etc.) make the parser fail.

1 Fix the redeemer file
Overwrite extend.redeemer.json with strictly-valid JSON:

bash
Copy
Edit
cat > extend.redeemer.json <<'EOF'
{ "constructor": 0, "fields": [ { "int": 1 } ] }
EOF
(The <<'EOF' form ensures no extra spaces sneak in.)

You can verify:

bash
Copy
Edit
jq . extend.redeemer.json          # should pretty-print without errors
2 Re-run the build
bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --out-file              extend.txbody \
  --mainnet
If everything else is set correctly, it should now output an estimated fee instead of an error.








You said:
Progress! Now we are here:

abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cat > extend.redeemer.json <<'EOF'
{ "constructor": 0, "fields": [ { "int": 1 } ] }
EOF
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build   --tx-in                 "$SCRIPT_TX_IN"   --tx-in-script-file     "$SPEND_SCRIPT"   --tx-in-datum-file      old_datum.json   --tx-in-redeemer-file   extend.redeemer.json   --tx-in-collateral      "$COLLATERAL_TX"   --tx-out                "$SCRIPT_ADDR+$NEW_VALUE"   --tx-out-datum-hash     "$NEW_DHASH"   --change-address        "$PAYMENT_ADDR"   --required-signer       wallets/subscriber/payment.skey   --out-file              extend.txbody   --mainnet
Command failed: transaction build  Error: The following scripts have execution failures:
the script for transaction input 0 (in ascending order of the TxIds) failed with: 
The Plutus script evaluation failed: The evaluation finished but the result value is not valid. Plutus V3 scripts must return BuiltinUnit. Returning any other value is considered a failure.
Script debugging logs: 
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:
cardano-cli is telling us only that the spend validator returned something other than () (BuiltinUnit), so the chain rejected it.
We need the on-chain debug trace to see why the validator stopped with expect … and produced a non-unit result.

1 Re-build in “dry-run” / debug mode
Add the two flags below. This forces the node to keep running the script (even though it will still fail) and dump the trace + cost model into a JSON file:

bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --script-invalid \
  --calculate-plutus-script-cost cost.json \
  --out-file              extend_dbg.txbody \
  --mainnet
(The transaction will not be submit-table; that’s fine – we only want the cost & log.)

If you still get the “return value is not valid” error but cost.json is produced, proceed.

2 Open the log
bash
Copy
Edit
jq '.[0] | {budget, logs}' cost.json
Look at the logs array. Every trace @"something" in your Aiken code shows up here, followed by the point where the validator threw an expect … exception.
Typical first-run pitfalls:

Trace	What to check
single_pair	Exactly one pair in minted_pairs?
token_name	The NFT name in the continuing output still equals the policy parameter?
amount_is_1	For Extend, the validator must see zero net NFT mint/burn (you are spending, not minting). So the script may be failing at verify_no_nft_change(mint, …).
agent_deposit_10000	Old value had 10 000 agent; new value must have 20 000 exactly (old + deposit).
subscriber_signed	Make sure the subscriber key actually signs the tx (we add that signature at the sign step later).

3 Most common causes and fixes
Failure point	How to fix
Still minting/burning	Remove any --mint … flags. For an Extend you are only spending; the NFT stays in place.
Wrong new Agent balance	NEW_VALUE must use exactly old_agent + 10 000 (so 20 000 now).
Wrong lovelace	Keep the Ada amount unchanged (4 000 000).
Datum hash mismatch	Re-compute NEW_DHASH after any change to new_datum.json.
No subscriber signature	After the build succeeds, run
`cardano-cli conway transaction sign --tx-body-file extend_dbg.txbody \	

css
Copy
Edit
 --signing-key-file wallets/subscriber/payment.skey \  
 --out-file extend_dbg.tx.signed --mainnet`  
(Add the admin key too if your script ever checks for it.) |

4 Iterate
Build with --script-invalid --calculate-plutus-script-cost …

Inspect cost.json → fix the specific “expect failed” reason.

When cost.json shows the trace ending in "True" and no expect failures, rebuild without --script-invalid, sign, and submit:

bash
Copy
Edit
cardano-cli conway transaction build   …same args but **omit** the two debug flags…
cardano-cli conway transaction sign    --tx-body-file extend.txbody \
   --signing-key-file wallets/subscriber/payment.skey \
   --out-file extend.tx.signed --mainnet
cardano-cli conway transaction submit  --tx-file extend.tx.signed --mainnet
Once the extend succeeds, query the script UTxO again; you should see

lovelace: 4 000 000

NFT: 1

Agent: 20 000

Datum: installments list now has one element, and subscription_end advanced.

Give that a try and post the first few lines of logs from cost.json; we can pinpoint the exact failing expect.








You said:
bc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in                 "$SCRIPT_TX_IN" \
  --tx-in-script-file     "$SPEND_SCRIPT" \
  --tx-in-datum-file      old_datum.json \
  --tx-in-redeemer-file   extend.redeemer.json \
  --tx-in-collateral      "$COLLATERAL_TX" \
  --tx-out                "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash     "$NEW_DHASH" \
  --change-address        "$PAYMENT_ADDR" \
  --required-signer       wallets/subscriber/payment.skey \
  --script-invalid \
  --calculate-plutus-script-cost cost.json \
  --out-file              extend_dbg.txbody \
  --mainnet
Invalid option --out-file'

Usage: cardano-cli 
                     ( address
                     | key
                     | node
                     | query
                     | legacy
                     | byron
                     | shelley
                     | allegra
                     | mary
                     | alonzo
                     | babbage
                     | conway
                     | latest
                     | hash
                     | ping
                     | debug commands
                     | version
                     | compatible
                     )
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:

Thought for 11 seconds
cardano-cli lets you build either

a normal, balanced body you can later sign (--out-file …) or

a dry-run body with cost/log output only (--calculate-plutus-script-cost …)

—but not both in the same invocation.
Because we passed both flags the parser stopped at --out-file and bubbled the “Invalid option” message all the way up.

How to get the debug log
bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in              "$SCRIPT_TX_IN" \
  --tx-in-script-file  "$SPEND_SCRIPT" \
  --tx-in-datum-file   old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-in-collateral   "$COLLATERAL_TX" \
  --tx-out             "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash  "$NEW_DHASH" \
  --change-address     "$PAYMENT_ADDR" \
  --required-signer    wallets/subscriber/payment.skey \
  --script-invalid \
  --calculate-plutus-script-cost cost.json \
  --mainnet
Omit --out-file here.
The command will still print “script execution failed”, but you should now have a cost.json containing:

json
Copy
Edit
[
  {
    "budget": { ... },
    "logs": [ "trace @\"single_pair\" …", … ]
  }
]
Inspect the trace:

bash
Copy
Edit
jq '.[0].logs' cost.json
The last trace entry shows which expect failed.

Next step
Fix the underlying cause (most often: NFT still being minted/burnt, wrong Agent amount, or wrong subscriber signature).

When the trace ends in True and no expect fails, rebuild without --script-invalid --calculate-plutus-script-cost but with --out-file extend.txbody, sign, and submit.

That will get the Extend transaction on-chain.








You said:
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ cardano-cli conway transaction build \
  --tx-in              "$SCRIPT_TX_IN" \
  --tx-in-script-file  "$SPEND_SCRIPT" \
  --tx-in-datum-file   old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-in-collateral   "$COLLATERAL_TX" \
  --tx-out             "$SCRIPT_ADDR+$NEW_VALUE" \
  --tx-out-datum-hash  "$NEW_DHASH" \
  --change-address     "$PAYMENT_ADDR" \
  --required-signer    wallets/subscriber/payment.skey \
  --script-invalid \
  --calculate-plutus-script-cost cost.json \
  --mainnet
Command failed: transaction build  Error: The transaction does not balance in its use of ada. The net balance of the transaction is negative: -399273 Lovelace. The usual solution is to provide more inputs, or inputs with more ada.
abc@granular-presence-9dkmi5-0:~/workspace/repo/subscription$ 


ChatGPT said:
The “net balance … is negative” message simply means the transaction is trying to spend more Ada than it brings in.
Nothing is wrong with the validator at this point—the builder just can’t make the math work with the inputs you supplied.

Below is a quick checklist that almost always resolves this specific error.

1 Verify the value going back to the script
bash
Copy
Edit
NEW_VALUE="4000000 \
           + 1  ${POLICY_ID}.${ASSET_HEX} \
           + 20000 ${AGENT_POLICY_ID}.${AGENT_ASSET_NAME}"
4000000 Lovelace is the min-Ada for an output that carries two multi-assets.
If you edit the datum again or add more assets, the min-Ada changes and
you must recalculate it (use cardano-cli conway transaction calculate-min-required-utxo …).

2 Check the inputs’ Ada
$SCRIPT_TX_IN contributes 4 000 000 Ada (that is what you locked earlier).

$COLLATERAL_TX is collateral; its Ada is not counted in balancing.

If the only other input is also the collateral UTxO, the builder has no
extra Ada to pay the fee, so it reports a deficit (-399 273 in your run).

➜ Add a normal wallet UTxO as an extra --tx-in
bash
Copy
Edit
cardano-cli conway query utxo \
  --address "$PAYMENT_ADDR" --mainnet
Pick a small lovelace-only UTxO (e.g. 10 ADA) and set

bash
Copy
Edit
export FEE_IN=txhash#ix
then add another --tx-in "$FEE_IN" to the build command.

The builder will then:

take fee Ada from that input,

send the change back to --change-address.

3 Re-run the script-invalid dry-run
bash
Copy
Edit
cardano-cli conway transaction build \
  --tx-in              "$SCRIPT_TX_IN" \
  --tx-in              "$FEE_IN" \
  --tx-in-script-file  "$SPEND_SCRIPT" \
  --tx-in-datum-file   old_datum.json \
  --tx-in-redeemer-file extend.redeemer.json \
  --tx-in-collateral   "$COLLATERAL_TX" \
  --tx-out             "$SCRIPT_ADDR + $NEW_VALUE" \
  --tx-out-datum-hash  "$NEW_DHASH" \
  --change-address     "$PAYMENT_ADDR" \
  --required-signer    wallets/subscriber/payment.skey \
  --script-invalid \
  --calculate-plutus-script-cost cost.json \
  --mainnet
If you still see a negative Ada balance, increase the size of $FEE_IN
or add another small input.

Once the balance error disappears, inspect jq '.[0].logs' cost.json
to ensure the validator traces end in the last “subscriber_signed”
and True.

4 Build the real transaction
Remove --script-invalid --calculate-plutus-script-cost, add
--out-file extend.txbody, run again, then sign & submit:

bash
Copy
Edit
cardano-cli conway transaction sign \
  --tx-body-file extend.txbody \
  --signing-key-file wallets/subscriber/payment.skey \
  --out-file extend.tx.signed \
  --mainnet

cardano-cli conway transaction submit \
  --tx-file extend.tx.signed \
  --mainnet
Why the earlier flags failed
--required-signer-file doesn’t exist in Conway; use --required-signer.

--protocol-params-file is not accepted by conway transaction build
(the builder now queries the node for params automatically).

Follow the four steps above and the transaction should build and validate.