import Foundation
import Testing
@testable import SwiftLocalization

@Suite struct LocalizationValueTests {
    @Test func literalIsKeptVerbatim() {
        let value: LocalizationValue = "Progress: 100%"
        #expect(value.key == "Progress: 100%")
        #expect(value.arguments.isEmpty)
    }

    @Test func interpolationBuildsFormatKeyAndTypedArguments() {
        let name = "Ada"
        let count = 3
        let small: Int32 = -2
        let unsigned: UInt = 7
        let byte: UInt8 = 255
        let ratio = 0.5
        let single: Float = 1.5
        let value: LocalizationValue = "\(name): \(count) \(small) \(unsigned) \(byte) \(ratio) \(single) \(ratio, specifier: "%.2f") 100%"
        #expect(value.key == "%@: %lld %d %llu %u %lf %f %.2f 100%%")
        #expect(value.arguments == [
            .string("Ada"), .integer(3), .integer(-2), .unsignedInteger(7), .unsignedInteger(255),
            .floatingPoint(0.5), .floatingPoint(1.5), .floatingPoint(0.5),
        ])
    }

    /// Keys must not depend on the target: `Int` is `%lld` on wasm32 too.
    @Test func integerSpecifiersDependOnTheTypeOnly() {
        func key(_ value: LocalizationValue) -> String { value.key }
        #expect(key("\(Int(-1))") == "%lld")
        #expect(key("\(Int64(-1))") == "%lld")
        #expect(key("\(Int32(-1))") == "%d")
        #expect(key("\(Int16(-1))") == "%d")
        #expect(key("\(Int8(-1))") == "%d")
        #expect(key("\(UInt(1))") == "%llu")
        #expect(key("\(UInt64(1))") == "%llu")
        #expect(key("\(UInt32(1))") == "%u")
        #expect(key("\(UInt16(1))") == "%u")
        #expect(key("\(UInt8(1))") == "%u")
        #expect(key("\(1) \(1 as UInt)") == "%lld %llu")

        let values: LocalizationValue = "\(Int.min) \(Int64.max) \(Int8.min) \(UInt.max) \(UInt64.max) \(UInt16.max)"
        #expect(values.arguments == [
            .integer(Int64(Int.min)), .integer(.max), .integer(-128),
            .unsignedInteger(UInt64(UInt.max)), .unsignedInteger(.max), .unsignedInteger(65535),
        ])
    }

    @Test func otherIntegerTypesUseTheWideSpecifiersAndClamp() {
        func value<T: BinaryInteger>(_ integer: T) -> LocalizationValue { "\(integer)" }
        // Through the generic entry point the type alone decides, whatever its width.
        #expect(value(Int8(-5)) == LocalizationValue(key: "%lld", arguments: [.integer(-5)]))
        #expect(value(UInt8(5)) == LocalizationValue(key: "%llu", arguments: [.unsignedInteger(5)]))
        #expect(value(Int(5)).key == "%lld")
        #expect(value(UInt(5)).key == "%llu")
    }

    @Test func keySelectionDoesNotInspectMemoryLayout() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftLocalization/LocalizationValue.swift")
        #expect(try !String(contentsOf: source, encoding: .utf8).contains("MemoryLayout"))
    }

    @Test func resourceKeepsKeyDistinctFromDefaultValue() {
        let count = 2
        let explicit = LocalizedResource("cart.count", defaultValue: "\(count) items")
        #expect(explicit.key == "cart.count")
        #expect(explicit.defaultValue.key == "%lld items")
        let inferred: LocalizedResource = "\(count) items"
        #expect(inferred.key == "%lld items")
        #expect(inferred.defaultValue.arguments == [.integer(2)])
    }
}

@Suite struct LocaleIdentifierTests {
    @Test(arguments: [
        ("en", "en"), ("EN-us", "en-US"), ("zh_hant_tw", "zh-Hant-TW"), ("ZH-HANS", "zh-Hans"),
        ("es-419", "es-419"), ("sl-rozaj-biske", "sl-rozaj-biske"), ("de-CH-1901", "de-CH-1901"),
        ("zh-yue-HK", "yue-HK"), ("en-US-u-ca-gregory", "en-US-u-ca-gregory"), ("en-x-Private", "en-x-private"),
        ("nl_BE.UTF-8", "nl-BE"), ("ca_ES@valencia", "ca-ES"), ("fil", "fil"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(LocaleIdentifier(validating: input)?.identifier == expected)
    }

    @Test(arguments: ["", "e", "en--US", "en-", "en-US-US", "x-private", "en-u", "en-ü", "1234", "en US"])
    func rejectsMalformedTags(input: String) {
        #expect(LocaleIdentifier(validating: input) == nil)
        #expect(LocaleIdentifier(input) == .undetermined)
    }

    @Test(arguments: [
        "en-u-ca-gregory-u-nu-latn", "en-U-ca-gregory-u-nu-latn", "en-a-bbb-a-ccc", "de-CH-t-en-u-nu-latn-T-fr",
    ])
    func rejectsRepeatedExtensionSingletons(input: String) {
        #expect(LocaleIdentifier(validating: input) == nil)
        #expect(LocaleIdentifier(input) == .undetermined)
    }

    @Test(arguments: [
        ("en-a-bbb-u-ca-gregory", "en-a-bbb-u-ca-gregory"),
        ("en-US-U-ca-gregory-nu-latn-T-fr", "en-US-u-ca-gregory-nu-latn-t-fr"),
        ("en-u-ca-gregory-x-private", "en-u-ca-gregory-x-private"),
        ("en-x-a-b-c", "en-x-a-b-c"),
        // Everything after `x` is private use, so a repeated letter there is not a singleton.
        ("en-u-ca-gregory-x-u-nu-u", "en-u-ca-gregory-x-u-nu-u"),
        ("en-x-x", "en-x-x"),
    ])
    func acceptsDistinctExtensionsAndPrivateUse(input: String, expected: String) {
        #expect(LocaleIdentifier(validating: input)?.identifier == expected)
    }

    @Test func exposesSubtags() {
        let locale: LocaleIdentifier = "sr_latn_rs"
        #expect(locale.language == "sr")
        #expect(locale.script == "Latn")
        #expect(locale.region == "RS")
        #expect(locale == LocaleIdentifier("SR-Latn-RS"))
    }

    @Test func fallbackChainTruncatesDeterministically() {
        #expect(LocaleIdentifier("zh-Hant-TW").fallbackChain.map(\.identifier) == ["zh-Hant-TW", "zh-Hant", "zh-TW", "zh"])
        #expect(LocaleIdentifier("de-CH-1901-u-co-phonebk").fallbackChain.map(\.identifier) == [
            "de-CH-1901-u-co-phonebk", "de-CH-1901", "de-CH", "de",
        ])
        #expect(LocaleIdentifier("pt-BR").fallbackChain.map(\.identifier) == ["pt-BR", "pt"])
        #expect(LocaleIdentifier("en").fallbackChain.map(\.identifier) == ["en"])
    }
}

@Suite struct PluralOperandsTests {
    @Test func distinguishesVisibleFractionDigits() {
        #expect(PluralOperands(decimal: "1") == PluralOperands(i: 1))
        #expect(PluralOperands(decimal: "1.0") == PluralOperands(i: 1, v: 1, w: 0, f: 0, t: 0))
        #expect(PluralOperands(decimal: "1.00") == PluralOperands(i: 1, v: 2, w: 0, f: 0, t: 0))
        #expect(PluralOperands(decimal: "-1.230") == PluralOperands(i: 1, v: 3, w: 2, f: 230, t: 23))
        #expect(PluralOperands(decimal: "0.05") == PluralOperands(i: 0, v: 2, w: 2, f: 5, t: 5))
        #expect(PluralOperands(-7) == PluralOperands(i: 7))
        #expect(PluralOperands(UInt64.max).i == UInt64.max)
    }

    @Test func appliesCompactExponent() {
        #expect(PluralOperands(decimal: "1c6") == PluralOperands(i: 1_000_000, c: 6))
        #expect(PluralOperands(decimal: "1.2c6") == PluralOperands(i: 1_200_000, c: 6))
        #expect(PluralOperands(decimal: "1.0000001c6") == PluralOperands(i: 1_000_000, v: 1, w: 1, f: 1, t: 1, c: 6))
        #expect(PluralOperands(decimal: "1.20e1") == PluralOperands(i: 12, v: 1, w: 0, f: 0, t: 0, c: 1))
    }

    @Test func keepsHugeIntegersLargeAndTheirLowDigits() throws {
        let operands = try #require(PluralOperands(decimal: "100000000000000000000000000000000001"))
        #expect(operands.i % 1_000_000 == 1)
        #expect(operands.i > 1_000_000_000_000_000_000)
        #expect(try #require(PluralOperands(decimal: "1c30")).i >= 1_000_000_000_000_000_000)
    }

    @Test(arguments: ["", "-", ".5", "1.", "1,5", "1e", "abc", "1.5x", "١"])
    func rejectsMalformedDecimals(input: String) {
        #expect(PluralOperands(decimal: input) == nil)
    }

    @Test func derivesOperandsFromDisplayedDouble() {
        #expect(PluralOperands(1.0, fractionDigits: 0) == PluralOperands(i: 1))
        #expect(PluralOperands(1.0, fractionDigits: 2) == PluralOperands(i: 1, v: 2))
        #expect(PluralOperands(1.5, fractionDigits: 1) == PluralOperands(i: 1, v: 1, w: 1, f: 5, t: 5))
        #expect(PluralOperands(.nan, fractionDigits: 1) == nil)
    }
}

@Suite struct DecimalTextTests {
    @Test(arguments: [
        (0.0, 2, "0.00"), (1.0, 0, "1"), (1.5, 0, "2"), (2.5, 0, "2"), (0.125, 2, "0.12"), (0.135, 2, "0.14"),
        (-1.005, 1, "-1.0"), (999.999, 2, "1000.00"), (1e21, 1, "1000000000000000000000.0"),
        (0.00001234, 7, "0.0000123"), (1234.5678, 6, "1234.567800"), (0.99, 0, "1"), (0.4, 0, "0"),
    ])
    func roundsHalfToEven(value: Double, precision: Int, expected: String) {
        #expect(DecimalText.fixed(value, precision: precision) == expected)
    }

    @Test func rendersShortestRepresentationWithoutPrecision() {
        #expect(DecimalText.fixed(0.1, precision: nil) == "0.1")
        #expect(DecimalText.fixed(1e-7, precision: nil) == "0.0000001")
        #expect(DecimalText.fixed(-12.0, precision: nil) == "-12.0")
        #expect(DecimalText.fixed(.infinity, precision: 2) == nil)
    }
}

@Suite struct CLDRPluralRulesTests {
    let rules = CLDRPluralRules()

    /// Every sample CLDR publishes for every locale and category.
    @Test func conformsToCLDRSamples() throws {
        var checked = 0
        var rows: Set<PluralRuleType> = []
        for line in cldrPluralSamples.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            try #require(fields.count == 4, "malformed fixture line: \(line)")
            let type = try #require(PluralRuleType(rawValue: fields[0]))
            let category = try #require(PluralCategory(rawValue: fields[1]))
            rows.insert(type)
            for locale in fields[2].split(separator: " ") {
                let identifier = try #require(LocaleIdentifier(validating: String(locale)))
                for sample in fields[3].split(separator: " ") {
                    let operands = try #require(PluralOperands(decimal: String(sample)), "sample \(sample)")
                    let actual = rules.category(for: operands, type: type, locale: identifier)
                    #expect(actual == category, "\(type) \(locale) \(sample)")
                    checked += 1
                }
            }
        }
        #expect(rows == [.cardinal, .ordinal])
        #expect(checked > 10_000)
    }

    @Test func distinguishesDecimalForms() {
        func cardinal(_ decimal: String, _ locale: LocaleIdentifier) -> PluralCategory? {
            PluralOperands(decimal: decimal).map { rules.category(for: $0, type: .cardinal, locale: locale) }
        }
        #expect(cardinal("1", "en") == .one)
        #expect(cardinal("1.0", "en") == .other)
        #expect(cardinal("1.00", "en") == .other)
        #expect(cardinal("1.0", "af") == .one)
        #expect(cardinal("1.5", "fr") == .one)
        #expect(cardinal("1c6", "fr") == .many)
        #expect(cardinal("1000000", "fr") == .many)
        #expect(cardinal("0", "lv") == .zero)
        #expect(cardinal("2", "ar") == .two)
        #expect(cardinal("1.5", "ru") == .other)
        #expect(cardinal("21", "ru") == .one)
    }

    @Test func selectsOrdinals() {
        func ordinal(_ value: Int, _ locale: LocaleIdentifier) -> PluralCategory {
            rules.category(for: PluralOperands(value), type: .ordinal, locale: locale)
        }
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101].map { ordinal($0, "en") }
            == [.one, .two, .few, .other, .other, .other, .other, .one, .two, .few, .one])
        #expect(ordinal(1, "fr") == .one)
        #expect(ordinal(2, "fr") == .other)
        #expect(ordinal(8, "it") == .many)
        #expect(ordinal(3, "cy") == .few)
    }

    @Test func matchesLocalesThroughFallback() {
        let one = PluralOperands(1)
        #expect(rules.category(for: PluralOperands(decimal: "1.5")!, type: .cardinal, locale: "pt-PT") == .other)
        #expect(rules.category(for: PluralOperands(decimal: "1.5")!, type: .cardinal, locale: "pt-BR") == .one)
        #expect(rules.category(for: one, type: .cardinal, locale: "en-Latn-GB-u-ca-gregory") == .one)
        #expect(rules.category(for: one, type: .cardinal, locale: "tlh") == .other)
        #expect(rules.category(for: one, type: .cardinal, locale: .undetermined) == .other)
        #expect(CLDRPluralRules.cldrVersion == "48")
    }
}

@Suite struct ResolverTests {
    typealias Variation = LocalizationCatalog.Variation

    static func catalog(_ entries: [String: [LocaleIdentifier: LocalizationCatalog.Localization]]) -> LocalizationCatalog {
        LocalizationCatalog(sourceLanguage: "en", entries: entries.mapValues { .init(localizations: $0) })
    }

    let resolver = LocalizationResolver(catalog: catalog([
        "greeting": ["en": .init(variation: .string("Hello")), "pt-BR": .init(variation: .string("Oi")),
                     "zh-Hant": .init(variation: .string("你好"))],
        "%lld items": [
            "en": .init(variation: .plural(.cardinal, [.one: .string("%lld item"), .other: .string("%lld items")])),
            "ar": .init(variation: .plural(.cardinal, [
                .zero: .string("لا عناصر"), .one: .string("عنصر"), .two: .string("عنصران"),
                .few: .string("%lld عناصر"), .many: .string("%lld عنصرًا"), .other: .string("%lld عنصر"),
            ])),
        ],
        "%lld place": ["en": .init(variation: .plural(.ordinal, [
            .one: .string("%lldst place"), .two: .string("%lldnd place"),
            .few: .string("%lldrd place"), .other: .string("%lldth place"),
        ]))],
        "%@ has %lld%% of %lf": ["en": .init(variation: .string("%3$.1f: %1$@ has %2$lld%%"))],
        "only.nl": ["nl": .init(variation: .string("Alleen"))],
        "broken.plural": ["en": .init(variation: .plural(.cardinal, [.one: .string("one")]))],
        "broken.device": ["en": .init(variation: .device(["mac": .string("mac")]))],
        "broken.substitution %lld": ["en": .init(variation: .string("%#@missing@"))],
        "unsupported %lld": ["en": .init(variation: .string("%05lld"))],
        "too.many %lld": ["en": .init(variation: .string("%lld %lld"))],
        "wrong.type %@": ["en": .init(variation: .string("%lld"))],
        "recursive %lld": ["en": .init(
            variation: .string("%#@a@"),
            substitutions: ["a": .init(argumentIndex: 1, formatSpecifier: "lld", variation: .string("%#@a@"))]
        )],
        "%lld of %lld": ["en": .init(
            variation: .string("%#@done@ of %#@total@"),
            substitutions: [
                "done": .init(formatSpecifier: "lld", variation: .plural(.cardinal, [.one: .string("%arg task"), .other: .string("%arg tasks")])),
                "total": .init(formatSpecifier: "lld", variation: .plural(.cardinal, [.one: .string("%lld (single)"), .other: .string("%arg")])),
            ]
        )],
    ]))

    private func reason(_ resource: LocalizedResource, locale: LocaleIdentifier = "en") -> LocalizationError.Reason? {
        #expect(throws: LocalizationError.self) { try resolver.resolve(resource, locale: locale) }?.reason
    }

    @Test func followsLanguageScriptRegionFallback() throws {
        #expect(try resolver.resolve("greeting", locale: "pt-BR") == "Oi")
        #expect(try resolver.resolve("greeting", locale: "pt-PT") == "Hello")
        #expect(try resolver.resolve("greeting", locale: "zh_hant_hk") == "你好")
        #expect(try resolver.resolve("greeting", locale: "zh-Hans") == "Hello")
        #expect(try resolver.resolve("greeting", locale: "en-AU-u-nu-latn") == "Hello")

        var configured = resolver
        configured.fallbackLocales = ["pt-BR"]
        #expect(try configured.resolve("greeting", locale: "pt-PT") == "Oi")
    }

    @Test(arguments: [(0, "لا عناصر"), (1, "عنصر"), (2, "عنصران"), (5, "5 عناصر"), (11, "11 عنصرًا"), (100, "100 عنصر")])
    func selectsArabicCardinals(count: Int, expected: String) throws {
        #expect(try resolver.resolve("\(count) items", locale: "ar-EG") == expected)
    }

    @Test(arguments: [(1, "1st place"), (2, "2nd place"), (3, "3rd place"), (4, "4th place"), (11, "11th place"), (22, "22nd place")])
    func selectsEnglishOrdinals(place: Int, expected: String) throws {
        #expect(try resolver.resolve("\(place) place", locale: "en") == expected)
    }

    @Test func formatsEscapedLiteralsAndMultipleTypedArguments() throws {
        let resource: LocalizedResource = "\("Ada") has \(40)% of \(2.25)"
        #expect(resource.key == "%@ has %lld%% of %lf")
        #expect(try resolver.resolve(resource, locale: "en") == "2.2: Ada has 40%")
        // Missing key: the default value is formatted instead.
        let missing: LocalizedResource = "\("Ada") scored \(40)% (\(2.25, specifier: "%.1f"))"
        #expect(resolver.string(for: missing, locale: "en") == "Ada scored 40% (2.2)")
    }

    @Test func expandsSubstitutionsWithImplicitArguments() throws {
        #expect(try resolver.resolve("\(1) of \(1)", locale: "en") == "1 task of 1 (single)")
        #expect(try resolver.resolve("\(2) of \(5)", locale: "en") == "2 tasks of 5")
    }

    @Test func reportsWhyResolutionFailed() {
        #expect(reason("nope") == .missingKey)
        #expect(reason("only.nl", locale: "fr") == .missingLocale)
        #expect(reason("broken.device") == .malformedVariation("device variation has no \"other\" case"))
        #expect(reason("broken.plural") == .missingPluralArgument)
        #expect(reason("broken.substitution \(1)") == .malformedVariation("unknown substitution \"missing\""))
        #expect(reason("unsupported \(1)") == .unsupportedFormat(specifier: "%05lld"))
        #expect(reason("too.many \(1)") == .missingArgument(position: 2))
        #expect(reason("wrong.type \("x")") == .incompatibleArgument(position: 1, specifier: "%lld"))
        #expect(reason("recursive \(1)") == .malformedVariation("substitutions are nested too deeply"))
        #expect(reason(LocalizedResource("%lld items", defaultValue: "\("x") items")) == .missingPluralArgument)
    }

    @Test func lenientLookupFallsBackToTheDefaultValue() {
        #expect(resolver.string(for: "nope", locale: "en") == "nope")
        #expect(resolver.string(for: LocalizedResource("only.nl", defaultValue: "Only"), locale: "fr") == "Only")
        #expect(resolver.string(for: LocalizedResource("only.nl", defaultValue: "Only"), locale: "nl") == "Alleen")
        #expect(resolver.string(for: "\(3) unknown things", locale: "fr") == "3 unknown things")
        // A default value that cannot be formatted is returned as written.
        #expect(resolver.string(for: "\(3, specifier: "%x") things", locale: "en") == "%x things")
    }

    @Test func usesInjectedServices() throws {
        struct Grouping: LocalizedNumberFormatter {
            func string(fromDecimal decimal: String, locale: LocaleIdentifier) -> String {
                "<\(decimal)|\(locale)>"
            }
        }
        struct AlwaysFew: PluralRuleProvider {
            func category(for operands: PluralOperands, type: PluralRuleType, locale: LocaleIdentifier) -> PluralCategory { .few }
        }
        // Supplied at initialization…
        let initialized = LocalizationResolver(catalog: resolver.catalog, pluralRules: AlwaysFew(), numberFormatter: Grouping())
        #expect(try initialized.resolve("\(21) place", locale: "en") == "<21|en>rd place")
        // …or replaced afterwards.
        var configured = resolver
        configured.setNumberFormatter(Grouping())
        #expect(try configured.resolve("\(1200) items", locale: "en-GB") == "<1200|en-GB> items")
        configured.setPluralRules(AlwaysFew())
        #expect(try configured.resolve("\(1) place", locale: "en") == "<1|en>rd place")
    }
}

@Suite struct PortabilityTests {
    /// The runtime target must stay free of Foundation and JavaScriptKit.
    @Test func runtimeTargetImportsOnlyTheStandardLibrary() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftLocalization")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        for file in files {
            let imports = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
                .filter { $0.hasPrefix("import ") || $0.contains(" import ") && !$0.hasPrefix("//") && !$0.contains("///") }
            #expect(imports.isEmpty, "\(file.lastPathComponent) imports a module: \(imports)")
        }
    }
}
