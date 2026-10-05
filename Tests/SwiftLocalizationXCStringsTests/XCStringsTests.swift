import Foundation
import SwiftLocalization
import SwiftLocalizationGeneratorCore
import SwiftLocalizationXCStrings
import Testing

/// The catalog shared by the decoding, resolution, and plugin integration tests.
func localizableFixture() throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Localizable.xcstrings")
    return try String(contentsOf: url, encoding: .utf8)
}

private func minimal(strings: String, version: String = "1.0") -> String {
    #"{"sourceLanguage":"en","strings":{\#(strings)},"version":"\#(version)"}"#
}

@Suite struct XCStringsDecodingTests {
    let fixture: String

    init() throws {
        fixture = try localizableFixture()
    }

    @Test func decodesTheSupportedSchema() throws {
        let catalog = try XCStringsDocument(parsing: fixture).catalog()
        #expect(catalog.sourceLanguage == "en")
        #expect(catalog.entries.count == 8)
        #expect(catalog.entries["Untranslated"]?.localizations.isEmpty == true)
        #expect(catalog.entries["cart.title"]?.localizations["zh-Hant"]?.variation == .string("購物車"))
        #expect(catalog.entries["%lld items"]?.localizations["en"]?.variation == .plural(.cardinal, [
            .one: .string("%lld item"),
            .other: .string("%lld items"),
        ]))
        let substitution = catalog.entries["%lld files in %lld folders"]?.localizations["en"]?.substitutions["folders"]
        #expect(substitution?.argumentIndex == 2)
        #expect(substitution?.formatSpecifier == "lld")
        #expect(catalog.entries["device.hint"]?.localizations["en"]?.variation == .device([
            "mac": .string("Click \"Buy\""),
            "other": .string("Tap \"Buy\""),
        ]))
    }

    @Test func reportsSyntaxErrorsWithPosition() {
        #expect(throws: XCStringsError(location: "2:3", message: "expected a string key")) {
            try XCStringsDocument(parsing: "{\n  sourceLanguage: 1\n}")
        }
        #expect(throws: XCStringsError.self) {
            try XCStringsDocument(parsing: #"{"a":1,"a":2}"#)
        }
    }

    @Test func rejectsUnsupportedVersionsAndMissingFields() {
        #expect(throws: XCStringsError.self) { try XCStringsDocument(parsing: minimal(strings: "", version: "2.0")) }
        #expect(throws: XCStringsError.self) { try XCStringsDocument(parsing: #"{"version":"1.0","strings":{}}"#) }
        #expect(throws: XCStringsError.self) { try XCStringsDocument(parsing: "[]") }
        #expect(throws: Never.self) { try XCStringsDocument(parsing: minimal(strings: "", version: "1.1")) }
    }

    @Test(arguments: [
        (#""k":{"localizations":{"en":{}}}"#, "expected a stringUnit with a value, or variations"),
        (#""k":{"localizations":{"not a tag":{"stringUnit":{"value":"v"}}}}"#, "\"not a tag\" is not a valid language tag"),
        (#""k":{"localizations":{"en":{"variations":{"plural":{"one":{"stringUnit":{"value":"v"}}}}}}}"#,
         "plural variation has no \"other\" case"),
        (#""k":{"localizations":{"en":{"variations":{"plural":{"lots":{"stringUnit":{"value":"v"}}}}}}}"#,
         "unknown plural category \"lots\""),
        (#""k":{"localizations":{"en":{"variations":{"width":{"20":{"stringUnit":{"value":"v"}}}}}}}"#,
         "unsupported variation kind \"width\""),
        (#""k":{"localizations":{"en":{"stringUnit":{"value":"v"}},"EN":{"stringUnit":{"value":"v"}}}}"#,
         "duplicate locale \"en\""),
    ])
    func rejectsMalformedCatalogs(strings: String, message: String) throws {
        let document = try XCStringsDocument(parsing: minimal(strings: strings))
        let error = #expect(throws: XCStringsError.self) { try document.catalog() }
        #expect(error?.message == message)
        #expect(error?.location.hasPrefix("strings.\"k\"") == true)
    }
}

@Suite struct XCStringsRoundTripTests {
    let fixture: String

    init() throws {
        fixture = try localizableFixture()
    }

    @Test func unchangedDocumentRoundTripsByteForByte() throws {
        #expect(try XCStringsDocument(parsing: fixture).serialized() == fixture)
        #expect(try XCStringsDocument(parsing: fixture + "\n").serialized() == fixture + "\n")
    }

    @Test func editsPreserveUnknownFields() throws {
        var document = try XCStringsDocument(parsing: fixture)
        try document.setStringUnit(key: "%lld items", locale: "nl", value: "%lld artikelen")
        try document.setStringUnit(key: "cart.title", locale: "nl", value: "Mandje", state: "needs_review")
        try document.setStringUnit(key: "Zebra", locale: "nl", value: "Zebra")
        try document.setStringUnit(key: "Apple", locale: "nl", value: "Appel")

        let output = document.serialized()
        #expect(output.contains("""
                  "futureEntryField" : [
                    1.50,
                    true,
                    null
                  ],
            """))
        #expect(output.contains(#"https:\/\/example.com\/cart"#))
        #expect(output.contains(#""extractionState" : "manual""#))

        let reparsed = try XCStringsDocument(parsing: output)
        #expect(reparsed.serialized() == output)
        let catalog = try reparsed.catalog()
        #expect(catalog.entries["%lld items"]?.localizations["nl"]?.variation == .string("%lld artikelen"))
        #expect(catalog.entries["cart.title"]?.localizations["nl"]?.variation == .string("Mandje"))
        #expect(catalog.entries["cart.title"]?.localizations["en"]?.variation == .string("Cart"))

        let keys = reparsed.root["strings"]?.object?.members.map(\.key)
        #expect(keys?.first == "%.1f km")
        #expect(keys?.contains("Apple") == true)
        #expect(keys?.last == "device.hint")
        #expect(keys.map { $0.firstIndex(of: "Apple")! < $0.firstIndex(of: "Progress: 100%")! } == true)
        #expect(keys.map { $0.firstIndex(of: "Zebra")! < $0.firstIndex(of: "cart.title")! } == true)
    }

    @Test func refusesToReplaceVariations() throws {
        var document = try XCStringsDocument(parsing: fixture)
        #expect(throws: XCStringsError.self) {
            try document.setStringUnit(key: "%lld items", locale: "en", value: "items")
        }
        #expect(document.serialized() == fixture)
    }

    @Test func parsesEscapesAndRestylesForeignLayouts() throws {
        let source = minimal(strings: #""ké😀\n":{"localizations":{"en":{"stringUnit":{"value":"a/b\t\"q\""}}}}"#)
        let document = try XCStringsDocument(parsing: source)
        #expect(try document.catalog().entries["ké😀\n"]?.localizations["en"]?.variation == .string("a/b\t\"q\""))
        let output = document.serialized()
        #expect(output.contains(#""ké😀\n" : {"#))
        #expect(output.contains(#""value" : "a/b\t\"q\"""#))
        #expect(try XCStringsDocument(parsing: output) == XCStringsDocument(parsing: XCStringsDocument(parsing: output).serialized()))
    }
}

@Suite struct SwiftCatalogEmitterTests {
    let fixture: String

    init() throws {
        fixture = try localizableFixture()
    }

    @Test func outputIsDeterministic() throws {
        let emitter = try SwiftCatalogEmitter(propertyName: "localizable", sourceFileName: "Localizable.xcstrings")
        let first = emitter.emit(try XCStringsDocument(parsing: fixture).catalog())
        // A second, independently built catalog has differently seeded dictionaries.
        var copy = LocalizationCatalog(sourceLanguage: "en")
        for (key, entry) in try XCStringsDocument(parsing: fixture).catalog().entries.reversed() {
            copy.entries[key] = entry
        }
        #expect(emitter.emit(copy) == first)
        #expect(first.hasPrefix("// Generated by SwiftLocalizationGenerator (format version 1) from Localizable.xcstrings.\n"))
        #expect(!first.contains("/Users/"))
        #expect(first.contains(#"entries["Untranslated"] = LocalizationCatalog.Entry(localizations: [:])"#))
        #expect(first.contains(#"LocalizationCatalog.Variation.string("Tap \"Buy\"")"#))

        let sortedKeys = first.split(separator: "\n").filter { $0.hasPrefix("        entries[\"") }.map(String.init)
        #expect(sortedKeys == sortedKeys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    }

    @Test(arguments: [
        ("Localizable.xcstrings", "localizable"),
        ("In-App Purchases.xcstrings", "inAppPurchases"),
        ("Foo-Bar.xcstrings", "fooBar"),
        ("Foo Bar.xcstrings", "fooBar"),
        ("Foo.Bar.xcstrings", "fooBar"),
        ("Foo.xcstrings", "foo"),
        ("settings.v2.final.xcstrings", "settingsV2Final"),
        ("snake_case.xcstrings", "snake_case"),
        ("NoExtension", "noExtension"),
        ("default.xcstrings", "default"),
        ("Class.xcstrings", "class"),
        ("2fa.xcstrings", "_2fa"),
        ("123.xcstrings", "_123"),
        ("Überschrift.xcstrings", "überschrift"),
        (".xcstrings", "catalog"),
        ("---.xcstrings", "catalog"),
    ])
    func derivesPropertyNames(fileName: String, expected: String) {
        let name = SwiftCatalogEmitter.propertyName(forFileName: fileName)
        #expect(name == expected)
        #expect(SwiftCatalogEmitter.isValidPropertyName(name))
    }

    @Test func writesReservedWordsInBackticks() throws {
        let emitter = try SwiftCatalogEmitter(propertyName: "default", sourceFileName: "Default.xcstrings", accessLevel: "public")
        #expect(emitter.emit(LocalizationCatalog(sourceLanguage: "en")).contains("public static let `default`: LocalizationCatalog"))
        let plain = try SwiftCatalogEmitter(propertyName: "_2fa", sourceFileName: "2fa.xcstrings")
        #expect(plain.emit(LocalizationCatalog(sourceLanguage: "en")).contains("    static let _2fa: LocalizationCatalog"))
    }

    @Test func assignsDistinctAccessorsInOrder() throws {
        let names = try SwiftCatalogEmitter.propertyNames(forCatalogs: [
            ("a/Localizable.xcstrings", "Localizable.xcstrings"),
            ("a/Foo-Bar.xcstrings", "Foo-Bar.xcstrings"),
            ("a/Foo.xcstrings", "Foo.xcstrings"),
            ("a/default.xcstrings", "default.xcstrings"),
        ])
        #expect(names == ["localizable", "fooBar", "foo", "default"])
    }

    @Test(arguments: [
        ("Foo-Bar.xcstrings", "Foo Bar.xcstrings", "fooBar"),
        ("Foo-Bar.xcstrings", "Foo.Bar.xcstrings", "fooBar"),
        ("Foo.xcstrings", "foo.xcstrings", "foo"),
        ("2fa.xcstrings", "_2fa.xcstrings", "_2fa"),
        ("Localizable.xcstrings", "Localizable.xcstrings", "localizable"),
    ])
    func rejectsCatalogsThatShareAnAccessor(first: String, second: String, name: String) {
        let error = #expect(throws: SwiftCatalogEmitter.NameError.self) {
            try SwiftCatalogEmitter.propertyNames(forCatalogs: [
                ("Sources/App/Other.xcstrings", "Other.xcstrings"),
                ("Sources/App/\(first)", first),
                ("Sources/App/Sub/\(second)", second),
            ])
        }
        #expect(error == .collision(name: name, first: "Sources/App/\(first)", second: "Sources/App/Sub/\(second)"))
        #expect(error?.description.contains("'Sources/App/\(first)' and 'Sources/App/Sub/\(second)'") == true)
        #expect(error?.description.contains("LocalizationCatalog.\(name)") == true)
    }

    @Test(arguments: ["", "_", "2fa", "foo bar", "foo-bar", "foo.bar", "`default`", "foo: Int = 0; static let bar", "a\nb", "$0"])
    func rejectsInvalidExplicitNames(name: String) {
        #expect(!SwiftCatalogEmitter.isValidPropertyName(name))
        #expect(throws: SwiftCatalogEmitter.NameError.invalidName(name)) {
            try SwiftCatalogEmitter(propertyName: name, sourceFileName: "Localizable.xcstrings")
        }
    }

    @Test(arguments: ["localizable", "_private", "default", "über", "a1_b2"])
    func acceptsValidExplicitNames(name: String) {
        #expect(throws: Never.self) {
            try SwiftCatalogEmitter(propertyName: name, sourceFileName: "Localizable.xcstrings")
        }
    }
}
