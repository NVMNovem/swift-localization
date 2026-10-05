import Foundation
import SwiftLocalization
import SwiftLocalizationGeneratorCore
import SwiftLocalizationXCStrings
import Testing

/// The catalog the plugin test target compiles; shared so the fixtures stay in one place.
private let fixture: String = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SwiftLocalizationPluginTests/Localizable.xcstrings")
    return try! String(contentsOf: url, encoding: .utf8)
}()

private func minimal(strings: String, version: String = "1.0") -> String {
    #"{"sourceLanguage":"en","strings":{\#(strings)},"version":"\#(version)"}"#
}

@Suite struct XCStringsDecodingTests {
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
    @Test func outputIsDeterministic() throws {
        let emitter = SwiftCatalogEmitter(propertyName: "localizable", sourceFileName: "Localizable.xcstrings")
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

    @Test func derivesPropertyNames() {
        #expect(SwiftCatalogEmitter.propertyName(forFileName: "Localizable.xcstrings") == "localizable")
        #expect(SwiftCatalogEmitter.propertyName(forFileName: "In-App Purchases.xcstrings") == "inAppPurchases")
        #expect(SwiftCatalogEmitter.propertyName(forFileName: "2fa.xcstrings") == "_2fa")
        #expect(SwiftCatalogEmitter.propertyName(forFileName: ".xcstrings") == "catalog")
        let emitter = SwiftCatalogEmitter(propertyName: "default", sourceFileName: "Default.xcstrings", accessLevel: "public")
        #expect(emitter.emit(LocalizationCatalog(sourceLanguage: "en")).contains("public static let `default`: LocalizationCatalog"))
    }
}
