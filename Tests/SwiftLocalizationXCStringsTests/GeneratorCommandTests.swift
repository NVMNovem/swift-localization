import SwiftLocalization
import SwiftLocalizationGeneratorCore
import Testing

private let catalog = #"{"sourceLanguage":"en","strings":{"k":{"localizations":{"en":{"stringUnit":{"value":"v"}}}}},"version":"1.0"}"#

@Suite struct GeneratorCommandParsingTests {
    private func command(_ arguments: [String]) throws -> GeneratorCommand {
        guard case .generate(let command) = try GeneratorCommand.parse(arguments) else {
            throw GeneratorCommand.Failure(message: "expected a generate action")
        }
        return command
    }

    private func failure(_ arguments: [String]) -> String? {
        #expect(throws: GeneratorCommand.Failure.self) { try GeneratorCommand.parse(arguments) }?.message
    }

    @Test func parsesJobsInOrder() throws {
        let parsed = try command(["a/Localizable.xcstrings", "--output", "out/a.swift", "b/Foo Bar.xcstrings", "-o", "out/b.swift"])
        #expect(parsed.jobs == [
            .init(input: "a/Localizable.xcstrings", output: "out/a.swift"),
            .init(input: "b/Foo Bar.xcstrings", output: "out/b.swift"),
        ])
        #expect(parsed.propertyNames == ["localizable", "fooBar"])
        #expect(parsed.accessLevel == "internal")
    }

    @Test func parsesOptions() throws {
        let parsed = try command(["--access-level", "public", "--name", "strings", "Localizable.xcstrings", "-o", "a.swift"])
        #expect(parsed.propertyNames == ["strings"])
        #expect(parsed.accessLevel == "public")
        #expect(try GeneratorCommand.parse(["--help"]) == .help)
        #expect(try GeneratorCommand.parse(["x.xcstrings", "-h"]) == .help)
    }

    @Test(arguments: ["", "_", "2fa", "foo bar", "foo-bar", "`default`", "foo: Int = 0; static let bar"])
    func rejectsAnInvalidExplicitName(name: String) {
        #expect(failure(["Localizable.xcstrings", "-o", "a.swift", "--name", name])
            == "error: --name: '\(name)' is not a valid Swift identifier for a catalog accessor")
    }

    @Test func rejectsAnExplicitNameForSeveralCatalogs() {
        // Reported whether or not the name itself is valid, and wherever the option appears.
        for name in ["shared", "2fa"] {
            #expect(failure(["--name", name, "A.xcstrings", "-o", "a.swift", "B.xcstrings", "-o", "b.swift"])
                == "error: --name cannot be used with more than one catalog")
        }
    }

    @Test func rejectsCatalogsThatShareAnAccessor() {
        #expect(failure(["x/Foo-Bar.xcstrings", "-o", "a.swift", "x/Sub/Foo Bar.xcstrings", "-o", "b.swift"])
            == "error: string catalogs 'x/Foo-Bar.xcstrings' and 'x/Sub/Foo Bar.xcstrings' both generate "
            + "'LocalizationCatalog.fooBar'; rename one of them so every catalog in a target has its own accessor")
    }

    @Test(arguments: [
        ([], "Usage: SwiftLocalizationGenerator"),
        (["A.xcstrings"], "error: no --output for 'A.xcstrings'\n"),
        (["A.xcstrings", "-o", "a.swift", "B.xcstrings"], "error: no --output for 'B.xcstrings'\n"),
        (["--output", "a.swift"], "error: --output must follow a catalog and name a file\n"),
        (["A.xcstrings", "-o", "a.swift", "-o", "b.swift"], "error: --output must follow a catalog and name a file\n"),
        (["A.xcstrings", "--output"], "error: --output must follow a catalog and name a file\n"),
        (["A.xcstrings", "-o", "a.swift", "--name"], "error: --name requires a value\n"),
        (["A.xcstrings", "-o", "a.swift", "--access-level", "open"], "error: --access-level must be internal, package, or public\n"),
        (["A.xcstrings", "-o", "a.swift", "--verbose"], "error: unexpected argument '--verbose'\n"),
    ] as [([String], String)])
    func reportsUsageErrors(arguments: [String], prefix: String) {
        let message = failure(arguments)
        #expect(message?.hasPrefix(prefix) == true)
        #expect(message?.contains("Usage: SwiftLocalizationGenerator") == true)
    }
}

@Suite struct GeneratorCommandOutputTests {
    struct Unreadable: Error, CustomStringConvertible {
        var description: String { "no such file" }
    }

    private func command(_ arguments: [String]) throws -> GeneratorCommand {
        guard case .generate(let command) = try GeneratorCommand.parse(arguments) else {
            throw GeneratorCommand.Failure(message: "expected a generate action")
        }
        return command
    }

    @Test func convertsEveryCatalog() throws {
        let outputs = try command(["dir/Localizable.xcstrings", "-o", "a.swift", "dir/Other.xcstrings", "-o", "b.swift", "--access-level", "package"])
            .outputs { _ in catalog }
        #expect(outputs.map(\.path) == ["a.swift", "b.swift"])
        #expect(outputs[0].contents.contains("package static let localizable: LocalizationCatalog"))
        #expect(outputs[0].contents.contains("from Localizable.xcstrings."))
        #expect(outputs[1].contents.contains("package static let other: LocalizationCatalog"))
        #expect(!outputs[0].contents.contains("dir/"))
    }

    @Test func returnsNothingWhenAnyCatalogFails() throws {
        let parsed = try command(["Good.xcstrings", "-o", "a.swift", "Bad.xcstrings", "-o", "b.swift"])
        let syntax = #expect(throws: GeneratorCommand.Failure.self) {
            try parsed.outputs { $0 == "Bad.xcstrings" ? "{\n  oops" : catalog }
        }
        #expect(syntax?.message == "Bad.xcstrings:2:3: error: expected a string key")

        let schema = #expect(throws: GeneratorCommand.Failure.self) {
            try parsed.outputs { $0 == "Bad.xcstrings" ? #"{"sourceLanguage":"en","strings":{"k":{"localizations":{"en":{}}}},"version":"1.0"}"# : catalog }
        }
        #expect(schema?.message
            == #"Bad.xcstrings: error: strings."k".localizations.en: expected a stringUnit with a value, or variations"#)

        let unreadable = #expect(throws: GeneratorCommand.Failure.self) {
            try parsed.outputs { path in
                if path == "Bad.xcstrings" { throw Unreadable() }
                return catalog
            }
        }
        #expect(unreadable?.message == "Bad.xcstrings: error: no such file")
    }
}
