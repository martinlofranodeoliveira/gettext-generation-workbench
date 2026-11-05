# Contributing

This is development version 0.1.0. Start with `docs/contract.md` and `docs/design.md`. General organization information is available at https://lofranotecnologia.com.br.

Prepare the exact qualified toolchain from the README, resolve dependencies with Bundler, then run:

```sh
bundle exec ruby test/run.rb
bundle exec ruby bin/catalog_workbench demo --assert
```

Both commands are offline once dependencies exist. Do not add runtime package downloads, telemetry or network/model dependencies. Use synthetic fixtures only; never submit private client code, real personal information, credentials or client catalogs. Contributions must be original or clearly licensed, with dependency licenses kept distinct from this project's MIT license.

Changes to accepted plural headers, worker boot order, executable profiles, control descriptors or signal/reap ordering require adversarial tests and an explicit contract review. Keep the header guard before all domain/plural access. Preserve manual output oracles and independent GNU msgunfmt inspection; do not replace them with comparisons against the same implementation's output.

For format changes add malformed, fuzzy, obsolete and printf mismatch cases. For lifecycle changes retain tests for normal completion, nested hanging descendants, output flooding, control EOF and four acknowledged pinned renderers. Do not use sleeps as pinning proof. Do not add broad temporary-directory sweeps or generation deletion.

Keep public errors code-only. Diagnostics must not disclose source strings, translations or input paths. Document any changed limits, normalization or supported constructs in both READMEs and the contract. Do not claim production readiness, translation completeness or test results without evidence.

Report security issues privately using the process in `SECURITY.md`, not a public issue containing exploit details.
