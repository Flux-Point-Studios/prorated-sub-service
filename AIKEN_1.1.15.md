# Aiken v1.1.15 Validator Syntax & Latest Version Guide

## Version Status and Latest Release

The version **v1.1.15+353f281** installed via Nix appears to include a specific commit (`353f281`) on top of Aiken 1.1.15. As of March 2025, **Aiken v1.1.15** is the latest stable release ([Releases · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/releases#:~:text=v1)). There is no publicly released v1.1.16 yet (v1.1.16 is listed as "unreleased" in the changelog). In other words, your Nix-installed version is essentially Aiken 1.1.15 (with a minor commit tweak) – so you are on the latest stable version.

- *Release Notes:* Aiken 1.1.15 was released on March 23, 2025. You can find the official release on GitHub, which confirms it as the current "Latest" release ([Releases · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/releases#:~:text=v1)). Any development commits beyond 1.1.15 (like `+353f281`) are not separate stable versions, just unreleased changes merged into the main branch for an upcoming version.

## Declaring Validators in Aiken v1.1.15 (Plutus V3)

In Aiken 1.1.15, **validators** are declared using the `validator` keyword followed by a name, optional **parameters**, and a block containing one or more **handler functions**. Each handler corresponds to a specific Cardano script purpose (e.g. spending, minting) and enforces the logic for that context ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=As%20you%20can%20see%2C%20a,known%20purposes)). The general syntax is:

```aiken
validator <Name>(<Param1>: Type1, <Param2>: Type2, ...) {
    <purpose1>(<args>) -> Bool {
       ...  // validation logic
    }
    <purpose2>(<args>) -> Bool {
       ... 
    }
    ... 
    else(<ctx>: ScriptContext) -> Bool {
       ...  // fallback for any other purpose
    }
}
```

Key points about the syntax and structure:

- **Validator Name:** You can name the validator (e.g. `my_validator`). This name will be used in generated addresses or policy IDs. (In older Aiken examples, an unnamed `validator { ... }` block was possible, but naming is recommended for clarity.)

- **Parameters (Optional):** You may parameterize the validator by listing parameters in parentheses after the name. These parameters act like constants embedded into the compiled script (they must be provided **before** building the validator script) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=Parameters)). For example, you might pass an `OutputReference` or other configuration value as a parameter. All handlers inside can access these parameters. *(In Aiken v1.1.13+, a fix ensured that parameters are correctly applied to **all** handlers of a validator) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=,management%20of%20Plutus%20blueprint%20files)).*

- **Handlers:** Inside the validator block, define one or more *handler functions* using the well-known purpose names. **The handler name must exactly match one of Cardano's script purposes:** `spend`, `mint`, `withdraw`, `publish`, `vote`, or `propose` ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=As%20you%20can%20see%2C%20a,known%20purposes)). (The latter three were introduced for Plutus V3 in the Cardano *Conway* era – Aiken 1.1.0 added support for new governance purposes like `vote` and `proposal` ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=schemas)).)

- **Handler Signatures:** Each handler is a function that must return a boolean (`Bool`). A return of `True` means the validation **succeeds** (the transaction is authorized), and a return of `False` (or a failure) means the validation fails and the transaction is not authorized ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=Every%20handler%20is%20a%20predicate,an%20invalid%20%2035%20assignment)). In practice, Aiken will wrap a `False` result in an error to signal script failure. You can also explicitly fail by calling `fail <"error message">` inside the handler.

- **Handler Arguments:** The arguments for handlers are **pre-defined by the purpose**:
  - For a **`spend`** handler (used for spending a UTXO at a validator address), the function takes **four** arguments: the **datum**, the **redeemer**, the **spent output reference**, and the **transaction context** ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=With%20the%20exception%20of%20the,function%20with%20exactly%20three%20arguments)). In Aiken, the datum is represented as an `Option<DatumType>` because the spent output **may** carry no datum or a datum of your custom type. The redeemer is your custom redeemer type, the output reference identifies which UTXO is being spent, and `Transaction` (often referred to as `self` in examples) provides the full context of the transaction.
    - *Example signature:* `spend(datum_opt: Option<MyDatum>, redeemer: MyRedeemer, input: OutputReference, self: Transaction) -> Bool { ... }`
    - The first argument will be `Some(datum)` if a datum is present, or `None` if not – you typically pattern-match or use `expect` to extract it ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%20%7B%20spend%28datum_opt%3A%20Option,%7D)).
  - For a **`mint`** handler (used for minting or burning tokens under a policy), the function takes **three** arguments: the **redeemer**, the **policy ID** (asset policy being acted on), and the **transaction context** ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%20,%7D)). (No datum is associated with pure minting policies.)
    - *Example signature:* `mint(redeemer: MyRedeemer, policy_id: PolicyId, self: Transaction) -> Bool { ... }`
    - Here `policy_id` is provided by Aiken by extracting the policy script's own ID from the context (so you can ensure you're operating on the expected policy), and `self` is the `Transaction` context. 
  - Other purposes (`withdraw`, `publish`, `vote`, `propose`) similarly have three arguments: a redeemer, a purpose-specific target (e.g. a stake credential for `withdraw` or governance specific ID for others), and the `Transaction`. Only `spend` uses a datum (and thus four arguments) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=With%20the%20exception%20of%20the,function%20with%20exactly%20three%20arguments)).
  
**Why this matters:** Cardano's on-chain runtime treats spending scripts and minting policies slightly differently in terms of arguments. A spending validator script expects 3 pieces of data (datum, redeemer, context), whereas a minting policy expects only 2 (redeemer, context) ([plutus - Validator always accepts and Mints (but it shouldn't) - Cardano Stack Exchange](https://cardano.stackexchange.com/questions/11313/validator-always-accepts-and-mints-but-it-shouldnt#:~:text=now%2C%20the%20key%20difference%20is,datum%2C%20redeemer%2C%20context)). Aiken's handler-based syntax ensures you use the correct function signature for each context, so that your compiled Plutus script has the right arity. (In older Aiken code, one might write a single function and manually inspect the `ScriptContext` purpose, but using separate `spend`/`mint` handlers is the modern, safer approach.)

- **Fallback Handler (Optional):** You can include an `else(...)` handler as a catch-all for any script purpose that isn't explicitly handled. The fallback `else` takes a single `ScriptContext` argument ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=A%20special%20handler%20can%20thus,recover%20your%20redeemer%20and%2For%20datum)) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=else%28_ctx%3A%20ScriptContext%29%20%7B%20fail%20%40,%7D)). If a transaction triggers the validator for a purpose with no matching handler, the `else` handler will run. This is useful if you want to explicitly handle "unsupported" cases (perhaps to always fail with a message). If you do **not** provide an `else` handler, Aiken implicitly provides a default that always fails (so unspecified purposes are not authorized) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=)). In practice, you only need `else` if you have a multi-purpose validator and want a custom behavior for unexpected purposes.

- **Public/Exported Validators:** If your validator is in the `validators/` directory of an Aiken project, it's automatically recognized and compiled. You do not need to mark it `pub` (public) – by convention, all validators in that folder are intended for compilation. (If you declare a validator in a normal module, you might use `pub validator` to export it.) Aiken had a bug in earlier versions where the formatter would remove a `pub` on validators, but this was fixed before 1.1.15 ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=Fixed)).

## Examples of Validator Declarations (v1.1.15)

To illustrate, here are a few examples of valid validator declarations in Aiken 1.1.15. These examples use Plutus V3 types from Aiken's standard library (e.g. `Transaction`, `OutputReference`, etc.) and assume appropriate `use` imports for those types.

- **Spending Validator Example:** A simple validator that spends a UTXO protected by a datum and redeemer. In this example, we require that the datum is present and then (hypothetically) always succeed (return true) after some logic. In practice you'd replace the `todo`/`True` with real checks.

  ```aiken
  use cardano/transaction.{Transaction, OutputReference}

  validator my_spending_validator {
    spend(datum: Option<MyDatum>, redeemer: MyRedeemer, input: OutputReference, self: Transaction) -> Bool {
      // Extract the actual datum from the Option, or fail if not present
      expect Some(d) = datum               -- ensure a datum was provided
      // TODO: validator logic goes here, using d, redeemer, input, self
      True                                -- placeholder: always succeeds
    }
  }
  ``` 

  **Explanation:** We declare `my_spending_validator` with a single `spend` handler. The handler takes `datum` (of type `Option<MyDatum>`), `redeemer` (`MyRedeemer` is a user-defined type), `input` (`OutputReference` identifying which UTXO is being spent), and `self` (`Transaction` context). The code uses `expect Some(d) = datum` to pattern-match the `Option` (this will fail the script if `datum` is `None`, i.e. missing or not in the expected format). After that, your business logic would go, and ultimately the function returns a Bool. In this skeleton we return `True` (meaning the spend is allowed) just as a placeholder. In real usage, you might have conditions like `d.field == 42` or similar before deciding to return True or calling `fail`. 

  This example follows the official documentation's pattern: the `spend` handler receives the four arguments and should return True/False ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=With%20the%20exception%20of%20the,function%20with%20exactly%20three%20arguments)). If compilation is successful, this will produce a Plutus script that expects a datum, redeemer, and context (with the datum type enforced as `MyDatum` via the Option wrapper).

- **Minting Policy (Minting Validator) Example:** A validator that controls a token mint/burn. Suppose we want to allow minting only if a certain condition is met (for simplicity, say the redeemer is a unit type and we always allow it – a real policy would check something in `Transaction`). 

  ```aiken
  use cardano/assets.{PolicyId}
  use cardano/transaction.{Transaction}

  validator my_token_policy {
    mint(_redeemer: Unit, policy_id: PolicyId, tx: Transaction) -> Bool {
      // TODO: validation logic (e.g. ensure certain UTXO is spent, or restrict quantity)
      True   -- allow minting for now
    }
  }
  ```

  **Explanation:** `my_token_policy` has a `mint` handler with three arguments: a redeemer (here we expect no particular data, so we use the built-in `Unit` type as redeemer), the `policy_id` (PolicyId) for the asset being minted, and `tx` (the transaction context). Inside, you can use `tx` to inspect the transaction's inputs, outputs, minted tokens, etc., and even use `policy_id` if needed (though typically `policy_id` is just the hash of this script itself). We return `True` to indicate the mint is allowed. If we wanted to restrict minting to once, for example, we could check that a particular UTXO is consumed in `tx.inputs` (see parameterized example below). According to Aiken's docs, every `mint` handler should have this 3-argument form ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%20,%7D)). The compiled script will expect only a redeemer and context at runtime (Aiken handles the `policy_id` internally by extracting it from context).

- **Multi-Purpose Validator with Parameter Example:** You can combine multiple handlers in one validator. For instance, the Aiken *"Gift Card"* example uses one validator with both a mint and a spend handler – minting an NFT in one transaction, then spending the UTXO in another. Let's sketch a simplified version of a multi-purpose validator that has a parameter:

  ```aiken
  use cardano/assets.{PolicyId}
  use cardano/transaction.{Transaction, OutputReference}

  /// A validator that can both mint an asset and later spend a UTXO, only once.
  validator one_shot(asset_ref: OutputReference) {
    mint(_rdmr: Unit, policy_id: PolicyId, tx: Transaction) -> Bool {
      // Ensure the specified UTXO was consumed in this tx (enforce one-shot mint)
      expect list.any(tx.inputs, fn (inp) { inp.output_reference == asset_ref })
         -- The designated UTXO must be spent to allow minting ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%28utxo_ref%3A%20OutputReference%29%20,of%20the%20logic%20goes%20here))
      True  -- allow mint if condition passes
    }

    spend(_datum: Option<DatumType>, _rdmr: Unit, input: OutputReference, tx: Transaction) -> Bool {
      // For spending, maybe no special condition besides that it can only happen after mint
      True  -- allow redeeming the UTXO freely (could add checks here)
    }

    else(_ctx: ScriptContext) -> Bool {
      fail "Unsupported action"  -- any other use of this script fails ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=else%28_ctx%3A%20ScriptContext%29%20%7B%20fail%20%40,%7D))
    }
  }
  ```

  **Explanation:** Here `one_shot` is a validator that takes a parameter `asset_ref` (of type `OutputReference`). We imagine `asset_ref` is the reference to a specific UTXO that must be spent exactly once to authorize the mint (a typical pattern to ensure one-time usage). In the `mint` handler, we use Aiken's `list.any` function to check that `asset_ref` is among the transaction's inputs (meaning that UTXO is being spent) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%28utxo_ref%3A%20OutputReference%29%20,of%20the%20logic%20goes%20here)). If not, we `expect` will fail the script. The `spend` handler (for the UTXO at this validator's address) doesn't impose additional conditions here – it always returns True, meaning once the asset is minted and locked at this script address, anyone can later redeem it. We also include an `else` fallback that rejects any other script purpose with an error. This ensures the validator cannot be misused in a context other than the intended mint or spend. 

  In practice, both handlers share state: for example, the minted asset could be the NFT that's locked in the UTXO. The **parameter** `asset_ref` is provided when we deploy or instantiate the script (e.g., via `aiken blueprint apply`). Importantly, as of Aiken 1.1.13+, you only need to supply the parameter once for the validator as a whole – Aiken will apply it to both the `mint` and `spend` handlers internally ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=,management%20of%20Plutus%20blueprint%20files)) (previously, there was a bug requiring per-handler input, now resolved).

  This multi-handler approach is possible because Aiken compiles a single Plutus Core script that can handle multiple purposes. Under the hood, the compiler ensures the correct behavior for each context. (For example, it will make sure the script has the right number of arguments and discriminates the `ScriptContext.purpose` appropriately when executed.)

**Note:** In older Aiken versions (and in some early examples), a validator might be written as a single function taking a `ScriptContext` and then distinguishing cases of `purpose` within the code (using a `when` or pattern match on `ScriptContext.purpose`). While that can still work (indeed, you could write one fallback handler that inspects all cases manually), the **preferred style in v1.1.15** is to use the dedicated handler syntax shown above. It leads to clearer code and fewer mistakes. The compiler will enforce, for instance, that a `mint` handler isn't accidentally used in a spending context or vice versa by matching the correct argument count and types ([plutus - Validator always accepts and Mints (but it shouldn't) - Cardano Stack Exchange](https://cardano.stackexchange.com/questions/11313/validator-always-accepts-and-mints-but-it-shouldnt#:~:text=now%2C%20the%20key%20difference%20is,datum%2C%20redeemer%2C%20context)).

## Breaking Changes and Notable Updates Around v1.1.15

Aiken's 1.1.x series introduced the multi-handler validator syntax and various improvements. Here are some important changes or things to be aware of if you are upgrading or encountering examples from different versions:

- **Multi-Handler Syntax vs. Single Function:** The ability to declare multiple handlers (`spend`, `mint`, etc.) in one validator became fully supported in late 1.0.x alphas and into 1.1.0. If you see older code with `validator { fn myValidator(...) -> Bool { ... } }` or handling `ScriptContext.purpose` manually, know that you can now split that logic into purpose-specific handlers. The new syntax is not only cleaner but prevents the accidental partial application issue (where a script with the wrong arity could always succeed if misused) ([plutus - Validator always accepts and Mints (but it shouldn't) - Cardano Stack Exchange](https://cardano.stackexchange.com/questions/11313/validator-always-accepts-and-mints-but-it-shouldnt#:~:text=datum%2C%20redeemer%2C%20context%20)) ([plutus - Validator always accepts and Mints (but it shouldn't) - Cardano Stack Exchange](https://cardano.stackexchange.com/questions/11313/validator-always-accepts-and-mints-but-it-shouldnt#:~:text=so%20the%20result%20of%20the,because%20no%20error%20is%20evaluated)).

- **Datum Now Passed as `Option<>`:** In the handler signatures, note that the datum for `spend` is an `Option<YourDatumType>`. In earlier iterations, one might have used a generic `Data` or a dummy unit if no datum, but Aiken now explicitly uses `Option` to make you handle the possibility of an absent datum. In practice, when a UTXO has a datum, it will be `Some(datum)`, and if somehow no datum were attached, it would be `None`. This was a design choice to encourage safer pattern matching on datums.

- **New Script Purposes (Plutus V3):** Aiken v1.1.0 added support for **Conway era script purposes** – specifically governance-related scripts like `vote` and `propose` (as well as `publish` for DRep registration in Cardano governance). These are only relevant if you are writing validators for those new features. They behave like other three-argument handlers (no datum). If you're just writing typical spending scripts or minting policies, nothing changes for you, but it's good to know those handler names exist (and are reserved keywords just like `spend` and `mint`).

- **Blueprint Parameter Application Fix:** If you use Aiken's blueprint feature (e.g. `aiken blueprint apply` to inject parameters into a compiled script), be aware that prior to v1.1.13 there was an issue where, in a multi-handler validator, parameters might not apply correctly to all handlers. This was fixed in v1.1.13 – now the parameter substitution applies to every handler of that validator uniformly ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=,management%20of%20Plutus%20blueprint%20files)). For example, a parameter like `utxo_ref` in our multi-handler example will be correctly embedded for both the `mint` and `spend` parts of the script in the generated artifact.

- **Blueprint Naming of Handlers:** Similarly, v1.1.14 fixed a bug in the blueprint JSON generation where multiple handlers would get misnamed. Previously, running `aiken blueprint apply` on a validator with several handlers could override the names/ABIs of all handlers to one of them (e.g. all got the name of the `mint` handler) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=%2A%20aiken,1122.%20%40KtorZ)). This was confusing, but it's resolved now. After the fix, each handler's entry in the blueprint (or each compiled script artifact) retains the correct name. For instance, a blueprint for `gift_card` would list something like `gift_card.spend` and `gift_card.mint` separately if needed, rather than conflating them. (A user reported in issue #1128 that `aiken blueprint apply` was overwriting titles of other validators' handlers; the Aiken team marked it fixed in the next release ([Blueprint apply overwrites titles of other validators · Issue #1128 · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/issues/1128#:~:text=However%2C%20the%20resultant%20blueprint%20has,settings.settings.spend)) ([Blueprint apply overwrites titles of other validators · Issue #1128 · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/issues/1128#:~:text=KtorZ%20%20%20commented%20,76)) – that fix is in 1.1.14, which is included in 1.1.15.)

- **Formatting and `pub` Keyword:** As mentioned, there was a minor formatting bug in earlier versions (around 1.0.28-alpha) where running the Aiken formatter would remove the `pub` from `pub validator` declarations. This is long since fixed ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=Fixed)). In 1.1.15 you can safely use `pub` if needed (though in the `validators` folder it's often not necessary to use `pub` at all).

- **Else Handler Edge Case:** A bug (#1015) that existed in earlier 1.1.x betas affected "else" handlers' generation in some cases (it was an internal code-gen issue where the fallback might not be generated correctly). This was fixed by the time of 1.1.11 ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=match%20at%20L558%20%2A%20aiken,needlessly%20formatting%20over%20multiple%20lines)). Just ensure you're on 1.1.15 (which you are) and you shouldn't run into those problems. The fallback should correctly catch unmatched purposes and enforce failure if you code it to.

- **Error Messaging Improvements:** The 1.1.x updates also improved some error messages related to validators. For example, the compiler will give a specific error if your validator returns false without failing (to remind you that returning False will actually cause a script failure exception) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=Changed)). It also notes which handler is running when you have multiple (useful when debugging with traces) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=%2A%20aiken,properly%20wrapped%20with%20a%20constr)). If you run with tracing on verbose, Aiken will indicate which handler (mint or spend) is being executed, which can help identify issues in multi-purpose scripts.

## Official Documentation & Further Reading

For more details, the **official Aiken documentation** is the best resource:
- The *"Validators"* section of the Language Tour covers handler syntax in depth ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%20,%7D)) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=With%20the%20exception%20of%20the,function%20with%20exactly%20three%20arguments)), including tables of what arguments each handler receives.
- The *"Common Design Patterns"* and example tutorials (e.g., the Gift Card example) demonstrate real multi-handler validators with parameters ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=The%20,as%20an%20NFT%20and%20it)) ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=validator%20gift_card,redeem)). These can be insightful for seeing how a Plutus V3 validator is structured in Aiken.
- The Aiken GitHub repository's CHANGELOG is detailed; for instance, it notes the fixes and changes we discussed (e.g., parameter passing fix ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=,management%20of%20Plutus%20blueprint%20files)), blueprint naming fix ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=%2A%20aiken,1122.%20%40KtorZ))).
- If you encounter strange behavior, check the GitHub issues – many have been resolved in recent versions. As of v1.1.15, there are no known open issues significantly affecting validator declarations or handler formatting. Most prior pain points (handler naming, parameter injection, etc.) have been addressed in 1.1.13–1.1.15 releases.

With the above in mind, using Aiken v1.1.15 you can confidently write Plutus V3 validators. Just follow the syntax for handlers, leverage the type system (for datum/redeemer types), and refer to the examples as needed. Your version is up-to-date, so you have all the latest fixes at your disposal. Happy building!

**Sources:**

- Aiken official documentation – *Validators* (multi-handler syntax, handler arguments) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%20,%7D)) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=With%20the%20exception%20of%20the,function%20with%20exactly%20three%20arguments)); *Fallback handler* ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=else%28_ctx%3A%20ScriptContext%29%20%7B%20fail%20%40,%7D)); *Parameters* ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=validator%20my_script%28utxo_ref%3A%20OutputReference%29%20,of%20the%20logic%20goes%20here)).  
- Aiken v1.1.15 Release info (GitHub) ([Releases · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/releases#:~:text=v1)) and CHANGELOG (notable fixes in 1.1.13–1.1.15) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=%2A%20aiken,1122.%20%40KtorZ)) ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=,management%20of%20Plutus%20blueprint%20files)).  
- Cardano Stack Exchange – explanation of validator argument differences (spending vs minting) ([plutus - Validator always accepts and Mints (but it shouldn't) - Cardano Stack Exchange](https://cardano.stackexchange.com/questions/11313/validator-always-accepts-and-mints-but-it-shouldnt#:~:text=now%2C%20the%20key%20difference%20is,datum%2C%20redeemer%2C%20context)).  
- Aiken Gift Card example – demonstrating mint and spend handlers in one validator ([Aiken | Gift Card](https://aiken-lang.org/example--gift-card#:~:text=The%20,as%20an%20NFT%20and%20it)).  
- Aiken Issue Tracker – resolution of multi-handler blueprint naming issue ([Blueprint apply overwrites titles of other validators · Issue #1128 · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/issues/1128#:~:text=However%2C%20the%20resultant%20blueprint%20has,settings.settings.spend)) ([Blueprint apply overwrites titles of other validators · Issue #1128 · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/issues/1128#:~:text=KtorZ%20%20%20commented%20,76)).

## Addendum: Issues Encountered and Solutions in Aiken 1.1.15 with stdlib 2.1.0

When working with Aiken 1.1.15 and stdlib 2.1.0, we encountered several specific issues that required resolution. This addendum documents these challenges and their solutions to help others working with this version.

### Module and Import Path Changes

1. **Collection module reorganization**: In stdlib 2.1.0, several modules were reorganized:
   - `aiken/dict` → `aiken/collection/pairs`
   - `aiken/hash` → `aiken/collection/hash`
   - Dictionary operations now use `pairs.get()` and `pairs.to_list()` instead of `dict.get()` and `dict.to_list()`

2. **Credential types moved**: Verification key types are now in the crypto module:
   - `aiken/transaction/credential` → `aiken/crypto/credential`
   - Import `VerificationKeyHash` from `aiken/crypto/credential`

3. **Time representation**: `PosixTime` is no longer a distinct type:
   - Time values are represented as simple `Int` values
   - Use `type Time = Int` for clarity if needed

4. **Local module resolution**: Modules in the `lib/` directory are imported without the "lib" prefix:
   - Incorrect: `use subscription/lib/subscription`
   - Correct: `use subscription`

5. **Transaction types reorganization**: Transaction-related types have been reorganized:
   - `OutputReference` must be imported from `cardano/transaction`
   - `ScriptContext` appears to be a built-in type that doesn't need to be imported
   - Value operations are available from `cardano/value` module

### Code Structure and Visibility

1. **Public constants**: Constants must be marked with `pub` to be accessible from other modules:
   ```aiken
   pub const day_in_ms: Int = 86400000
   pub const subscription_amount: Int = 10000
   ```

2. **Helper function placement**: Helper functions must be defined at the module level:
   - Cannot define named functions inside validator handlers
   - Define all helpers at the top level for use across handlers
   - Example:
     ```aiken
     fn get_token_amount(output, policy_id, asset_name) -> Int {
       when pairs.get(value.tokens(output.value, policy_id), asset_name) is {
         Some(amount) -> amount
         None -> 0
       }
     }
     
     validator subscription() {
       // Call the helper from inside handlers
       spend(...) -> Bool {
         get_token_amount(...)
       }
     }
     ```

3. **Validator handler signatures**: Each handler must have the correct signature:
   - `spend` handler: `(datum_opt: Option<Datum>, redeemer, own_ref, ctx) -> Bool`
   - `mint` handler: `(redeemer, policy_id, ctx) -> Bool`
   - Return type must be explicitly marked as `-> Bool`

These changes reflect the evolution of the Aiken syntax and standard library. By following these patterns, you can successfully write and compile validators with Aiken 1.1.15 and stdlib 2.1.0.



# OutputReference in Aiken v1.1.15 (Stdlib 2.1.0)

## Definition and Module Path 
In Aiken **v1.1.15** (using standard library v2.1.0), **`OutputReference`** is a data type representing a unique reference to a UTxO (unspent transaction output) on Cardano. It is defined as a record with two fields: a transaction hash and an output index. In code, it looks like: 

```aiken
OutputReference { transaction_id: TransactionId, output_index: Int }
``` 

This means an `OutputReference` contains the **ID of the transaction** that produced the output and the **index of that output** in the transaction ([aiken/transaction - Cardano-Fans/acca](https://cardano-fans.github.io/acca/aiken/transaction.html#outputreference#:~:text=An%20,that%20produced%20that%20output)). It is essentially equivalent to a *TxOutRef* (transaction output reference) in Plutus terms, uniquely identifying an on-chain output ([aiken/transaction - Cardano-Fans/acca](https://cardano-fans.github.io/acca/aiken/transaction.html#outputreference#:~:text=An%20,that%20produced%20that%20output)).

**Module path:** The `OutputReference` type lives in the Cardano standard library module `cardano/transaction`. To use it in your Aiken code, you should import it from that module (along with related types like `Transaction`) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Faddress.,Transaction%2C%20OutputReference)). For example: 

```aiken
use cardano/transaction.{Transaction, OutputReference}
``` ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Faddress.,Transaction%2C%20OutputReference))

## No Renaming or Changes in v1.1.15 
No type renaming or restructuring was introduced for `OutputReference` in Aiken v1.1.15. The name and location of this type remain the same as in previous 1.x versions. The official v1.1.15 release notes and changelog contain **no mention of any changes** to `OutputReference`, indicating it remains stable in this release ([aiken/CHANGELOG.md at main · aiken-lang/aiken · GitHub](https://github.com/aiken-lang/aiken/blob/main/CHANGELOG.md#:~:text=%2A%20aiken,irrespective%20of%20the%20trace%20level)). In other words, you should continue to use `OutputReference` as-is (there was no switch to a different name or module in v1.1.15).

## Prelude vs Manual Import 
`OutputReference` is **not included in Aiken's default Prelude**, since the Prelude only provides fundamental types/functions and not the Cardano-specific types. The Cardano stdlib modules (e.g. `cardano/transaction`) must be added to your project (usually via `aiken add aiken-lang/stdlib`) and imported explicitly in each file where you use them ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Faddress.,Transaction%2C%20OutputReference)). This means you **must import** `OutputReference` from the `cardano/transaction` module in order to use it; it isn't in scope by default. The Aiken documentation demonstrates this by always importing `OutputReference` from `cardano/transaction` at the top of the validator file ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Faddress.,Transaction%2C%20OutputReference)).

## Example: Using `OutputReference` in a Validator Signature 
To use `OutputReference` in a validator, include it in the validator's parameter list or handler signature. In Aiken, a **spend validator** can directly take the spending UTxO's reference as an argument. For instance, the official docs show a validator with a `spend` handler that has an `OutputReference` parameter for the UTxO being spent:

```aiken
use cardano/transaction.{Transaction, OutputReference}

validator my_script {
  spend(datum_opt: Option<MyDatum>, redeemer: MyRedeemer, input: OutputReference, self: Transaction) {
    expect Some(datum) = datum_opt
    ...  // your validation logic
  }
}
``` ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Ftransaction.))

Here, `input: OutputReference` in the `spend` handler signature will be populated with the reference (transaction ID and index) of the output currently being spent by this script. In a minting policy, you might instead pass an `OutputReference` as a **parameter** to the validator itself (outside the handlers) if you need to lock a specific UTxO as part of the policy logic. 

In summary, to use `OutputReference` in v1.1.15:
- Import it from `cardano/transaction` (it's not in Prelude) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Faddress.,Transaction%2C%20OutputReference)).  
- Use it as the type for UTxO reference parameters. No special rename or workaround is needed in v1.1.15 – just use `OutputReference` directly.  
- In a validator, include an `OutputReference` in the function signature (e.g. the spend handler's arguments) to get the UTxO's reference, as shown above ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Ftransaction.)). 

This approach is the correct and idiomatic way to reference transaction outputs in Aiken 1.1.15 with stdlib 2.1.0, according to the official Aiken documentation and standard library definitions ([aiken/transaction - Cardano-Fans/acca](https://cardano-fans.github.io/acca/aiken/transaction.html#outputreference#:~:text=An%20,that%20produced%20that%20output)) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Ftransaction.)).

**Sources:** The Aiken standard library docs for **v2.1.0** (compatible with Aiken 1.1.15) and the Aiken user manual examples were used to confirm these details ([aiken/transaction - Cardano-Fans/acca](https://cardano-fans.github.io/acca/aiken/transaction.html#outputreference#:~:text=An%20,that%20produced%20that%20output)) ([Aiken | Validators](https://aiken-lang.org/language-tour/validators#:~:text=use%20cardano%2Ftransaction.)).