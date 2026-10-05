# SwiftLocalization

A portable localization system for Swift that works through Swift Package
Manager without Xcode. The runtime uses only the Swift standard library, so it
builds for Apple platforms, Linux, Windows, and WebAssembly.

This is an independent project. It is not an official Swift package.

## What is implemented

| Area | Status |
| --- | --- |
| `LocalizationValue` / `LocalizedResource` with typed interpolation | Implemented |
| BCP 47 normalization and truncation fallback (`LocaleIdentifier`) | Implemented |
| CLDR 48 cardinal and ordinal plural rules, decimal operands | Implemented |
| Catalog model, resolver, substitutions, device variations | Implemented |
| `.xcstrings` reader with non-destructive round trip | Implemented (host-side target) |
| `SwiftLocalizationGenerator` and `SwiftLocalizationPlugin` | Implemented |
| Foundation and JavaScript `Intl` adapters (localized digits, grouping) | Planned |
| `SwiftLocalizationCommandPlugin` (source discovery, catalog updates) | Planned |
| Loading catalogs at run time instead of compiling them in | Planned |

## Using the runtime

```swift
// Package.swift
.target(
    name: "App",
    dependencies: [.product(name: "SwiftLocalization", package: "swift-localization")],
    plugins: [.plugin(name: "SwiftLocalizationPlugin", package: "swift-localization")]
)
```

Put `Localizable.xcstrings` in the target. The plugin generates
`LocalizationCatalog.localizable` (the property is named after the file) in
its work directory; the checked-in catalog is never rewritten by a build.

The accessor is the file name without its extension in lower camel case, with
every character that cannot be in an identifier treated as a word break:
`In-App Purchases.xcstrings` becomes `inAppPurchases`. Two catalogs of one
target that would get the same accessor, such as `Foo-Bar.xcstrings` and
`Foo Bar.xcstrings`, fail the build with a diagnostic naming both.

```swift
import SwiftLocalization

let resolver = LocalizationResolver(catalog: .localizable)

let count = 3
resolver.string(for: "cart.title", locale: "nl")           // "Winkelwagen"
resolver.string(for: "\(count) items", locale: "pl")       // "3 elementy"
resolver.string(for: LocalizedResource("cart.count", defaultValue: "\(count) items"), locale: "en")
```

String literals and interpolations become `LocalizedResource` values through
`ExpressibleByStringInterpolation`; no macro or wrapper is needed. As with
`String.LocalizationValue`, `"\(count) items"` has the key `%lld items`
(`%@` for strings, `%lf` for `Double`), and a literal `%` next to an
interpolation is written `%%`. Integer specifiers depend on the type only,
never on the target: `Int` and `Int64` are `%lld`, `UInt` and `UInt64` are
`%llu`, the 8-, 16-, and 32-bit types are `%d` or `%u`, and any other
`BinaryInteger` is `%lld` or `%llu` with its value clamped to 64 bits.

`string(for:locale:)` never fails: when the catalog cannot answer, the default
value is formatted instead. `resolve(_:locale:)` throws a `LocalizationError`
whose reason is one of `missingKey`, `missingLocale`, `malformedVariation`,
`missingPluralArgument`, `missingArgument`, `incompatibleArgument`, or
`unsupportedFormat`.

A UI framework can build on this in its own repository, for example with a
`Text(_ resource: LocalizedResource)` initializer. No UI integration lives
here.

### Resolution rules

- **Fallback** is by truncation only and is the same on every host:
  `zh-Hant-TW`, `zh-Hant`, `zh-TW`, `zh`; then each of the resolver's
  `fallbackLocales`; then the catalog's source language. The process locale is
  never consulted.
- **Plural categories** come from the rules of the locale whose localization
  matched. Operands follow Unicode TR35, so `1`, `1.0`, and `1.00` are
  different: a `Double` is classified by the digits its format specifier
  displays (`%.1f` of `1.0` is `other` in English).
- **Format strings** support `%%`, `%@`, `%d %i %u` with any length modifier,
  `%f` with an optional precision, positional arguments (`%2$@`), and
  `%#@name@` substitutions with `%arg`. Flags, widths, and other conversions
  are reported as `unsupportedFormat`, not approximated.
- A localization is treated as a format string only when the resource has
  arguments or the localization has substitutions.

## Implementing a backend

Two services are injected into the resolver, and both have portable defaults:

```swift
struct IntlNumbers: LocalizedNumberFormatter {
    // `decimal` is locale-neutral: optional "-", ASCII digits, optional "." and digits.
    func string(fromDecimal decimal: String, locale: LocaleIdentifier) -> String { … }
}

var resolver = LocalizationResolver(catalog: .localizable)
resolver.numberFormatter = IntlNumbers()        // default: VerbatimNumberFormatter
resolver.pluralRules = CLDRPluralRules()        // default; or any PluralRuleProvider
resolver.deviceCategory = "mac"                 // for device variations
```

Another catalog format only has to produce a `LocalizationCatalog`.

## The `.xcstrings` frontend

Supported schema: format version `1.x` with `sourceLanguage`, `strings`, and
per-localization `stringUnit`, plural and device `variations` (including
nesting), and `substitutions` (`argNum`, `formatSpecifier`, `variations`).
Every string unit with a value is used, whatever its `state`.

Unknown-field policy: the reader keeps the whole JSON tree, including member
order and the spelling of numbers, so fields it does not interpret survive a
read-modify-write unchanged. A catalog in Xcode's layout that is not edited
serializes to the bytes it was read from; a catalog in another layout is
rewritten in Xcode's. Unknown variation kinds, unknown plural categories,
invalid language tags, and an unsupported major version are errors that name
the offending path, never silently dropped.

The frontend is the internal target `SwiftLocalizationXCStrings`. It is used
by the generator and is not part of the runtime product.

## Known limitations

- Locale normalization is syntactic. Deprecated aliases (`iw` for `he`),
  likely subtags (`zh-TW` implying `zh-Hant`), and CLDR parent locales
  (`es-MX` to `es-419`) are not applied; use `fallbackLocales` where needed.
- The default number formatter does not localize digits, grouping, or decimal
  separators. That is the job of a platform adapter.
- `%f` rounds the shortest round-trip decimal form of a `Double` half-to-even,
  which can differ from C `printf` in the last digit for values that are not
  exactly representable.
- A top-level plural variation is driven by the first numeric argument.
- `.xcstrings` has no ordinal variations; `Variation.plural(.ordinal, …)` is
  available to catalogs built in code.
- Source discovery is not implemented. When it is, it will be
  convention-based: Swift exposes no public compiler hook for third-party
  localization types, so a scanner can only recognize documented patterns, and
  runtime correctness must not depend on it.
- A resolver holds one catalog; choosing a table is up to the caller.

## Migration

From Apple-only code: keep your `.xcstrings` files. Keys produced by
`LocalizedResource` interpolation follow the conventions of the keys Xcode
extracts for `String(localized:)` and `LocalizedStringResource` (there is no
Darwin parity test yet), so
`String(localized: "\(count) items")` becomes
`resolver.string(for: "\(count) items", locale: locale)`.

Toward a future official cross-platform API: `LocalizedResource` mirrors
`LocalizedStringResource` (key, default value) and `LocalizationValue` mirrors
`String.LocalizationValue`. Keep these types at your module boundaries so they
can be swapped for the official ones.

## Plural data

Plural rules are generated from Unicode CLDR 48 (`unicode-org/cldr-json`
48.2.3) and checked in. Consumer builds never download or regenerate them. See
[Tools/CLDRPluralGenerator](Tools/CLDRPluralGenerator/README.md). The data is
Copyright © Unicode, Inc. and used under the
[Unicode License V3](Tools/CLDRPluralGenerator/Data/LICENSE).

## Development

```console
swift package describe
swift build
swift test
```
