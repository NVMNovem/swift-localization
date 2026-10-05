import Foundation
import Testing

// These tests run the real `SwiftLocalizationGenerator` executable, so they
// cover the wiring in its `main.swift` as well as the command logic.

#if !os(Windows)
@Suite struct GeneratorExecutableTests {
    let directory: TemporaryDirectory
    let generator: URL

    init() throws {
        directory = try TemporaryDirectory()
        generator = try generatorExecutable()
    }

    private func generate(_ arguments: [String]) throws -> ProcessResult {
        try run(generator, arguments, in: directory.url)
    }

    @Test func generatesEveryCatalog() throws {
        let first = try directory.write(catalog(greeting: "One"), to: "Localizable.xcstrings")
        let second = try directory.write(catalog(greeting: "Two"), to: "Sub/In-App Purchases.xcstrings")
        let result = try generate([
            first.path, "--output", directory.file("a.swift").path,
            second.path, "-o", directory.file("b.swift").path,
            "--access-level", "public",
        ])
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        let a = try String(contentsOf: directory.file("a.swift"), encoding: .utf8)
        let b = try String(contentsOf: directory.file("b.swift"), encoding: .utf8)
        #expect(a.contains("public static let localizable: LocalizationCatalog"))
        #expect(a.contains(#"LocalizationCatalog.Variation.string("One")"#))
        #expect(b.contains("public static let inAppPurchases: LocalizationCatalog"))
        #expect(b.contains("from In-App Purchases.xcstrings."))
        // No host-specific data in generated output.
        #expect(!a.contains(directory.url.path) && !b.contains(directory.url.path))
    }

    @Test(arguments: ["2fa", "foo bar", "foo: Int = 0; static let bar", "_"])
    func rejectsAnInvalidExplicitName(name: String) throws {
        let input = try directory.write(catalog(greeting: "One"), to: "Localizable.xcstrings")
        let result = try generate([input.path, "--output", directory.file("out.swift").path, "--name", name])
        #expect(result.status == 1)
        #expect(result.output == "error: --name: '\(name)' is not a valid Swift identifier for a catalog accessor\n")
        #expect(try swiftFiles(in: directory.url).isEmpty)
    }

    @Test func rejectsAnExplicitNameForSeveralCatalogs() throws {
        let first = try directory.write(catalog(greeting: "One"), to: "First.xcstrings")
        let second = try directory.write(catalog(greeting: "Two"), to: "Second.xcstrings")
        let result = try generate([
            first.path, "--output", directory.file("a.swift").path,
            second.path, "--output", directory.file("b.swift").path,
            "--name", "shared",
        ])
        #expect(result.status == 1)
        #expect(result.output == "error: --name cannot be used with more than one catalog\n")
        #expect(try swiftFiles(in: directory.url).isEmpty)
    }

    @Test func rejectsCatalogsThatShareAnAccessor() throws {
        let first = try directory.write(catalog(greeting: "One"), to: "Foo-Bar.xcstrings")
        let second = try directory.write(catalog(greeting: "Two"), to: "Sub/Foo Bar.xcstrings")
        let result = try generate([
            first.path, "--output", directory.file("a.swift").path,
            second.path, "--output", directory.file("b.swift").path,
        ])
        #expect(result.status == 1)
        #expect(result.output.contains("'\(first.path)' and '\(second.path)'"))
        #expect(result.output.contains("'LocalizationCatalog.fooBar'"))
        #expect(try swiftFiles(in: directory.url).isEmpty)
    }

    @Test func writesNothingWhenALaterCatalogIsMalformed() throws {
        let good = try directory.write(catalog(greeting: "One"), to: "Good.xcstrings")
        let bad = try directory.write("{\n  \"version\" : \"1.0\",\n  \"strings\" : {,}\n}", to: "Bad.xcstrings")
        let result = try generate([
            good.path, "--output", directory.file("good.swift").path,
            bad.path, "--output", directory.file("bad.swift").path,
        ])
        #expect(result.status == 1)
        #expect(result.output == "\(bad.path):3:16: error: expected a string key\n")
        #expect(try swiftFiles(in: directory.url).isEmpty)
    }

    @Test func reportsUsageErrors() throws {
        let missing = try generate([directory.file("Absent.xcstrings").path, "--output", directory.file("out.swift").path])
        #expect(missing.status == 1)
        #expect(missing.output.hasPrefix("\(directory.file("Absent.xcstrings").path): error: "))

        let unknown = try generate(["--frobnicate"])
        #expect(unknown.status == 1)
        #expect(unknown.output.hasPrefix("error: unexpected argument '--frobnicate'\nUsage: SwiftLocalizationGenerator"))

        let help = try generate(["--help"])
        #expect(help.status == 0)
        #expect(help.output.hasPrefix("Usage: SwiftLocalizationGenerator"))
        #expect(try swiftFiles(in: directory.url).isEmpty)
    }
}
#endif
