# subscription

Write validators in the `validators` folder, and supporting functions in the `lib` folder using `.ak` as a file extension.

```aiken
validator my_first_validator {
  spend(_datum: Option<Data>, _redeemer: Data, _output_reference: Data, _context: Data) {
    True
  }
}
```

## Building

```sh
aiken build
```

## Configuring

**aiken.toml**
```toml
[config.default]
network_id = 41
```

Or, alternatively, write conditional environment modules under `env`.

## Testing

You can write tests in any module using the `test` keyword. For example:

```aiken
use config

test foo() {
  config.network_id + 1 == 42
}
```

To run all tests, simply do:

```sh
aiken check
```

To run only tests matching the string `foo`, do:

```sh
aiken check -m foo
```

## Documentation

If you're writing a library, you might want to generate an HTML documentation for it.

Use:

```sh
aiken docs
```

## Resources

Find more on the [Aiken's user manual](https://aiken-lang.org).



In **Aiken v1.1.15**, the blueprint apply command was deliberately simplified so that **each invocation only accepts one static parameter** interactively and then exits immediately citeturn2search4. Because of this, if you run:

bash
aiken blueprint apply \
  --module subscription_mint \
  --validator subscription_mint


without telling Aiken where to write the updated blueprint, it just prints the new JSON to stdout, and the next time you try to supply --in first.json it can’t find any file named first.json—hence the “Invalid or missing project’s blueprint file” error citeturn5view0.

## 1. Build your project blueprint

First, compile your project to generate the initial plutus.json:

bash
rm -rf build
aiken build --plutus-version v3

This creates plutus.json in your project root (the **blueprint** that describes all your validators and their parameter schemas) citeturn0search0.

## 2. Apply parameters one‑by‑one with --out and --in

Since each run only applies one parameter, follow this pattern:

1. **First parameter**  
   
bash
   aiken blueprint apply \
     --module subscription_mint \
     --validator subscription_mint \
     --out first.json

   – You’ll be prompted for nft_asset_name interactively.  
   – The resulting blueprint (with that parameter filled) is written to first.json citeturn4search0.

2. **Second parameter**  
   
bash
   aiken blueprint apply \
     --in first.json \
     --module subscription_mint \
     --validator subscription_mint \
     --out second.json

   – Now you’re prompted for talos_policy_id, and the fully‑formed blueprint goes to second.json citeturn3view0.

3. **Third parameter**  
   
bash
   aiken blueprint apply \
     --in second.json \
     --module subscription_mint \
     --validator subscription_mint \
     --out third.json

   – You’ll be prompted for talos_asset_name.  

4. **Fourth parameter**  
   
bash
   aiken blueprint apply \
     --in third.json \
     --module subscription_mint \
     --validator subscription_mint \
     > full_params.json

   – Finally you’re asked for admin, and the complete blueprint is on stdout (redirected into full_params.json) citeturn6search0.

Each time, --in <file> loads the last state, --out <file> saves the new state—so you never lose the earlier parameters and avoid “missing blueprint” errors.

## 3. Non‑interactive (CBOR) shortcut

If you’d rather skip interactive prompts entirely, you can:

1. Prepare a CBOR file containing **all** your parameters in order (e.g. via a small Aiken test or a CBOR tool).
2. Feed it in one shot:
   
bash
   aiken blueprint apply \
     --module subscription_mint \
     --validator subscription_mint \
     -- \
     --bytes-file params.cbor \
     --out full_params.json

   This bypasses interactive prompting and applies every parameter at once citeturn2search0.

## 4. Future UX improvements

Aiken v1.1.16+ (coming soon) enhances this flow by allowing a single --in file to accumulate **all** parameters automatically and propagating them across multiple handlers in one go citeturn3view0turn2search2. Once you upgrade, you’ll still use --out and --in, but you’ll only need two invocations instead of N.

---

**References**  
- **Blueprint apply single‑param behavior**: CHANGELOG v1.1.15 (“blueprint apply now expects only one OPTIONAL argument…”) citeturn2search4  
- **Interactive CLI group**: Aiken Getting Started CLI docs (“Once compiled, look at the aiken blueprint command group…”) citeturn4search0  
- **Cumbersome one‑by‑one interface**: GitHub Issue #937 (“command-line provides a way to apply… one-by-one”) citeturn3view0  
- **CBOR file feeding**: GitHub Issue #1127 (“format for blueprint apply… --bytes-file…”) citeturn5view0  
- **Validator parameters overview**: Language Tour “Validators” (parameters are embedded at build time) citeturn6search0  
- **Design patterns for parameterized validators**: Common Design Patterns (one‑shot minting uses OutputReference) citeturn6search1  
- **Blueprint JSON spec**: Hello, World! tutorial (blueprint described in plutus.json) citeturn0search1  
- **Gift Card example of apply params**: Gift Card tutorial (apply params programmatically) citeturn6search2  
- **UX fix in next release**: GitHub Issue #994 (merged UX improvements) citeturn3view0turn2search2