# CLDRPluralGenerator

Maintainer-only tool that turns the vendored CLDR plural data into the
checked-in, Foundation-free Swift tables used by `CLDRPluralRules`.

It is a separate Swift package on purpose: it is not a target of
`swift-localization`, so consumer builds never compile it, run it, or touch
the network.

## Pinned data

`Data/` holds the inputs exactly as published:

| File | Purpose |
| --- | --- |
| `SOURCE` | Repository, release tag, and commit the files were taken from |
| `plurals.json`, `ordinals.json` | `cldr-core/supplemental` cardinal and ordinal rules |
| `LICENSE` | Unicode License V3, which covers the data and the generated tables |
| `SHA256SUMS` | Checksums of the three files above |

Current pin: `unicode-org/cldr-json` tag `48.2.3` (CLDR 48).

## Outputs

- `Sources/SwiftLocalization/Plurals/CLDRPluralRules+Generated.swift`: locale
  tables and one compiled rule set per distinct set of conditions. Identical
  rule sets are shared between locales and between cardinal and ordinal rules.
- `Tests/SwiftLocalizationTests/CLDRPluralSamples+Generated.swift`: every
  `@integer` and `@decimal` sample CLDR publishes, with ranges expanded, for
  the conformance test. Samples keep their decimal form (`1`, `1.0`, `1.00`,
  `1c6`).

Both are committed. Never edit them by hand.

## Regenerating

```console
Tools/CLDRPluralGenerator/regenerate.sh
```

This verifies `Data/` against `SHA256SUMS`, then rewrites both outputs. It is
offline and deterministic: with unchanged data it produces no diff.

## Updating CLDR

1. Set the new `tag` and `commit` in `Data/SOURCE`.
2. Run `UPDATE_CHECKSUMS=1 Tools/CLDRPluralGenerator/fetch-cldr.sh` and review
   the diff of `Data/`, including `LICENSE`.
3. Run `Tools/CLDRPluralGenerator/regenerate.sh`, then `swift test` at the
   repository root.
4. Update the version mentioned in the root `README.md`.

The generator fails on rule syntax it does not know rather than guessing.
