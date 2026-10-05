import Foundation
import SwiftLocalization
import SwiftLocalizationXCStrings
import Testing

/// Resolution against the catalog decoded from Tests/Fixtures/Localizable.xcstrings.
/// The integration tests check that the plugin-generated form of the same
/// catalog resolves identically.
@Suite struct CatalogResolutionTests {
    let resolver: LocalizationResolver

    init() throws {
        resolver = LocalizationResolver(catalog: try XCStringsDocument(parsing: localizableFixture()).catalog())
    }

    private func itemCount(_ count: Int) -> LocalizedResource { "\(count) items" }

    @Test func catalogHasEveryKey() {
        #expect(resolver.catalog.sourceLanguage == "en")
        #expect(resolver.catalog.entries.keys.sorted() == [
            "%.1f km", "%@ owes %@", "%lld files in %lld folders", "%lld items",
            "Progress: 100%", "Untranslated", "cart.title", "device.hint",
        ])
    }

    @Test func resolvesLiteralsAndFallsBack() {
        let title = LocalizedResource("cart.title", defaultValue: "Cart")
        #expect(resolver.string(for: title, locale: "nl-BE") == "Winkelwagen")
        #expect(resolver.string(for: title, locale: "zh-Hant-TW") == "購物車")
        #expect(resolver.string(for: title, locale: "fr") == "Cart")
        #expect(resolver.string(for: "Progress: 100%", locale: "nl") == "Voortgang: 100%")
        #expect(resolver.string(for: "Untranslated", locale: "nl") == "Untranslated")
    }

    @Test(arguments: [(1, "1 element"), (3, "3 elementy"), (5, "5 elementów"), (22, "22 elementy"), (112, "112 elementów")])
    func selectsPolishPlurals(count: Int, expected: String) {
        #expect(resolver.string(for: itemCount(count), locale: "pl") == expected)
    }

    @Test func expandsSubstitutions() {
        let files = 1, folders = 3
        let resource: LocalizedResource = "\(files) files in \(folders) folders"
        #expect(resolver.string(for: resource, locale: "en") == "1 file in 3 folders")
    }

    @Test func reordersPositionalArguments() {
        let resource: LocalizedResource = "\("Ada") owes \("Grace")"
        #expect(resolver.string(for: resource, locale: "nl") == "Grace is verschuldigd aan Ada")
        #expect(resolver.string(for: resource, locale: "en") == "Ada owes Grace")
    }

    @Test func selectsPluralFromDisplayedFractionDigits() {
        // "1.0" has a visible fraction digit, so English selects `other`.
        let one: LocalizedResource = "\(1.0, specifier: "%.1f") km"
        #expect(resolver.string(for: one, locale: "en") == "1.0 kilometers")
    }

    @Test func selectsDeviceVariation() {
        var resolver = resolver
        #expect(resolver.string(for: "device.hint", locale: "en") == "Tap \"Buy\"")
        resolver.deviceCategory = "mac"
        #expect(resolver.string(for: "device.hint", locale: "en") == "Click \"Buy\"")
    }
}
