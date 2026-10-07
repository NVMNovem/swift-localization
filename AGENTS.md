# SwiftLocalization contributor instructions

## Scope

These instructions apply to the entire `swift-localization` repository.

Build a portable Swift localization system that works through Swift Package
Manager without requiring Xcode. It must support Apple platforms, WebAssembly
(including Embedded Swift for the runtime), Linux, and Windows while keeping its public model compatible in spirit with
Swift localization APIs.

This repository is standalone infrastructure. It must not know about, import,
modify, or contain integration code for any consuming application or
third-party UI framework. Dependency direction is always:

```text
consumer                     --->  SwiftLocalization
SwiftLocalization            -X->  consumer
```

A UI framework may add `Text` overloads in its own repository, and a separate
bridge package may depend on both projects. Neither belongs here. Neighboring
repositories may be inspected for requirements or inspiration, but their files
and instructions are out of scope unless the user explicitly expands the task.

## Current package state

The package requires SwiftPM 6.3 or later (`swift-tools-version: 6.3`) and
currently contains:

- `SwiftLocalization`: the runtime library product. Standard library only,
  and Embedded-compatible; see "Embedded Swift compatibility".
- `SwiftLocalizationXCStrings`: the `.xcstrings` frontend, an internal
  Foundation-free target used by the generator.
- `SwiftLocalizationGeneratorCore` and `SwiftLocalizationGenerator`: the
  deterministic Swift emitter and command logic, and the thin executable
  that wraps them.
- `SwiftLocalizationPlugin`: the build-tool plugin product.
- `Tests/Fixtures`: the shared `.xcstrings` fixture and `PluginConsumer`, a
  package template the integration tests build with the real plugin in a
  temporary directory. Do not apply the plugin to a target of this package:
  that makes every build of the package, including a cross-compiled runtime,
  build the host generator.
- `Tools/CLDRPluralGenerator`: a separate, maintainer-only package that
  regenerates the checked-in CLDR plural tables from pinned data. It must
  never become a target of this package or run during a consumer build.

Not yet present: Foundation and Web `Intl` adapters, the command plugin, and
source discovery. `README.md` tracks implemented, planned, and limited
behavior; keep it current.

Before changing the manifest, inspect `git status` and preserve unrelated or
user-authored changes.

Reserved names:

- `SwiftLocalization`: primary runtime library product and target.
- `SwiftLocalizationPlugin`: build-tool plugin product and target.
- `SwiftLocalizationGenerator`: executable invoked by the build-tool plugin.
- `SwiftLocalizationCommandPlugin`: optional command plugin for explicitly
  requested source discovery or catalog updates.

Avoid giving a plugin and runtime library the same product or target name.

## Intended user experience

SwiftLocalization supplies framework-neutral structured values and resolution
APIs. Downstream UI frameworks should be able to offer familiar calls such as:

```swift
Text("cart.title")
Text("\(count) items")
```

Those `Text` overloads are examples of downstream integration, not API that
this package implements. The core should use contextual string literals and
`ExpressibleByStringInterpolation` so it can preserve the key, typed arguments,
and formatting metadata until a locale is selected.

Do not require a `#localized` macro or wrapper at every call site. Macros may be
investigated as optional tooling, but ordinary localization must not depend on
one. Do not use private compiler attributes or underscored SwiftUI semantics.

## Architectural boundaries

Keep the following boundaries explicit. Separate targets are appropriate once
their dependency or platform requirements differ; do not create empty targets
only to satisfy a speculative diagram.

### Runtime model

- Define format-neutral keys, localized values, interpolation arguments,
  locale identifiers, and resolution interfaces.
- Do not expose `.xcstrings` JSON types or generated-code details as public API.
- Keep public value types `Sendable` and deterministic whenever their stored
  values permit it.
- Avoid Foundation in the portable core when practical, especially if it would
  pull ICU into a WebAssembly binary.
- Never import JavaScriptKit in the portable core.

### Embedded Swift compatibility

Consumers with an Embedded-compatible core depend on the runtime, so the
`SwiftLocalization` target must keep compiling for Embedded Swift. This
applies to the runtime target only; the `.xcstrings` frontend, generator,
plugin, and tests are host-side.

- Do not store or pass protocol existentials (`any P`). Take services as
  `some P` and store them as closures over the concrete type, as
  `LocalizationResolver` does for plural rules and number formatting.
- Do not use key paths, `Mirror`, `String(describing:)`, `as?` casts to
  protocols, or untyped `throws`. Use typed throws with a concrete error.
- Do not make generated catalog code depend on anything the runtime could
  not offer under these rules.
- An API that cannot be expressed this way is a design problem to solve in
  the runtime, not a reason to drop the Embedded build.

### Catalog frontend

- Use `.xcstrings` as the first authoring and interchange format, not as the
  permanent runtime abstraction.
- Convert it to a neutral internal representation so another catalog frontend
  can replace or coexist with it later.
- Isolate Apple-specific schema and version handling.
- Preserve unknown JSON fields during read-modify-write operations whenever
  possible; do not destructively normalize files produced by newer Xcode
  versions.
- Keep a localization key distinct from its source-language value even when an
  Apple API infers one from the other.

### Runtime resolution

- Resolve catalogs, fallback, variations, typed substitutions, and formatting
  independently from source discovery.
- Normalize locale identifiers according to BCP 47 and make fallback explicit
  and deterministic.
- Use proper cardinal and ordinal plural categories. Never approximate plural
  selection with `count == 1`.
- Define behavior for missing keys, missing locales, malformed variations,
  incompatible substitutions, and unsupported formats.
- Never let build tooling depend implicitly on the host process locale.

### Platform services

- Foundation and JavaScriptKit integrations belong in separate adapter targets
  if and when they are required.
- A Web adapter may use JavaScript `Intl`, but JavaScriptKit types must not leak
  into public core APIs.
- SwiftPM traits may make an adapter optional, but traits are not a substitute
  for a clean target boundary. Verify dependency resolution and WebAssembly
  binary-size behavior before adopting them.
- Platform adapters provide locale and formatting services; UI-framework
  adapters do not belong in this repository.

## Plugin responsibilities

The build-tool plugin and any future command plugin have different jobs.

### `SwiftLocalizationPlugin`

- Read declared `.xcstrings` inputs and invoke
  `SwiftLocalizationGenerator` through a declared tool dependency.
- Generate deterministic derived Swift or runtime data only inside the plugin
  work directory.
- Declare precise input and output files so incremental builds are correct.
- Never rewrite a checked-in catalog during a normal build.
- Keep Foundation use in the host-side plugin or generator from leaking into
  the runtime dependency graph.

### `SwiftLocalizationCommandPlugin`

- Add this only when an explicit developer command is needed to discover
  strings, validate sources, or update checked-in catalogs.
- Request write permission only for commands that genuinely modify package
  files.
- Make catalog changes reviewable, deterministic Git changes.
- Keep extraction policies configurable and separate from catalog parsing.

## Source discovery

Swift does not expose a public compiler hook that lets third-party localization
types join the compiler's localization extraction machinery. A SwiftSyntax
scanner can support a documented set of patterns, but it is not a substitute
for type-checked compiler semantics.

- Never claim to discover every localizable expression.
- Do not interpret arbitrary `String` values as localization keys.
- Recognized call patterns must be configurable and must not require importing
  the frameworks whose syntax is recognized.
- Emit actionable diagnostics for ambiguous or unsupported expressions.
- Runtime correctness must never depend on extraction having found every use.
- Keep discovery optional and replaceable by a future compiler facility.

## API evolution and official Swift compatibility

- Prefer conventions familiar from `LocalizedStringResource`,
  `String.LocalizationValue`, and `LocalizedStringKey` without declaring types
  in the `Foundation` or `SwiftUI` modules.
- Avoid unnecessary public types and overloads that prevent coexistence with
  official localization APIs.
- Add adapters to official types at package boundaries when available.
- Before adding a public symbol, consider how it could map to or be retired in
  favor of a future official cross-platform API.
- Do not advertise this project as an official Swift package.

## Generated output

- Identical inputs and generator versions must produce byte-for-byte stable
  output.
- Sort keys and normalize serialization to avoid noisy diffs.
- Never include timestamps, absolute paths, or host-specific data.
- Include a schema or generator version when generated representations may
  evolve.
- Mark generated files clearly with their source of truth and regeneration
  command. Never hand-edit them.

## Dependencies

- Keep runtime targets dependency-light and cross-platform.
- Keep build-time dependencies out of the runtime graph.
- Do not add Foundation solely for minor conveniences that can be implemented
  correctly with the standard library.
- Do not casually reimplement Unicode, CLDR plural rules, locale negotiation,
  or internationalized formatting. Use a defined platform service or a pinned,
  versioned data source.
- Before adding a dependency, check supported platforms, transitive
  dependencies, binary-size cost, license, maintenance, and Swift 6 concurrency
  compatibility.
- Runtime catalog lookup must not require network access.

## Verification

Use the narrowest meaningful checks while iterating, then run the package-level
checks before handing off a completed change:

```console
swift package describe
swift build
swift test
```

After any change to `Sources/SwiftLocalization`, also build the runtime for
Embedded Swift. It is not covered by `swift test`, and the SDK must be used
with its matching compiler:

```console
swiftly run swift build --swift-sdk swift-6.3.3-RELEASE_wasm-embedded --target SwiftLocalization +6.3.3
```

As targets are added, tests should cover:

- literal and interpolated localization values;
- escaped literals and multiple typed arguments;
- non-English cardinal and ordinal plural categories;
- BCP-47 normalization and language/script/region fallback;
- missing keys and malformed catalogs;
- `.xcstrings` decoding and non-destructive round trips;
- deterministic generator output and incremental plugin inputs/outputs;
- parity fixtures shared by Foundation and Web `Intl` adapters where possible;
- compilation of the core without JavaScriptKit and, where intended, without
  Foundation;
- compilation of the runtime target for Embedded Swift.

Tests must not depend on the developer's locale, time zone, Xcode installation,
or network access unless explicitly marked as integration tests. When matching
an Apple API, add Darwin parity coverage where possible while keeping portable
expectations in platform-neutral fixtures.

## Documentation

- Distinguish implemented behavior, planned behavior, and known limitations.
- State that source discovery is convention-based until Swift exposes a public
  compiler extension point.
- Document the supported `.xcstrings` schema surface and unknown-field policy.
- Include examples for runtime consumers, backend implementers, and plugin use.
- Maintain migration guidance both from Apple-only localization code and toward
  a future official cross-platform implementation.

## Decision rule

Prefer boundaries that can later hand responsibility to official Swift APIs,
but do not introduce speculative abstractions. Add a protocol or adapter only
at a real boundary: catalog format, resolver, formatter, locale provider,
platform service, or source discovery.
