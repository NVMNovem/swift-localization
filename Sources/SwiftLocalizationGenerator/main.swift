import Foundation
import SwiftLocalizationGeneratorCore
import SwiftLocalizationXCStrings

// Converts one `.xcstrings` catalog to Swift source. Foundation is used here
// for file access only; it does not reach the runtime library.

let usage = """
    Usage: SwiftLocalizationGenerator <catalog.xcstrings> --output <file.swift>
               [--name <property>] [--access-level internal|package|public]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var input: String?
var output: String?
var name: String?
var accessLevel = "internal"

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "-o", "--output":
        output = arguments.popFirst()
    case "--name":
        name = arguments.popFirst()
    case "--access-level":
        guard let level = arguments.popFirst(), ["internal", "package", "public"].contains(level) else {
            fail("error: --access-level must be internal, package, or public\n" + usage)
        }
        accessLevel = level
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard !argument.hasPrefix("-"), input == nil else { fail("error: unexpected argument '\(argument)'\n" + usage) }
        input = argument
    }
}
guard let input, let output else { fail(usage) }

let inputURL = URL(fileURLWithPath: input)
let fileName = inputURL.lastPathComponent
do {
    let source = try String(contentsOf: inputURL, encoding: .utf8)
    let catalog = try XCStringsDocument(parsing: source).catalog()
    let emitter = SwiftCatalogEmitter(
        propertyName: name ?? SwiftCatalogEmitter.propertyName(forFileName: fileName),
        sourceFileName: fileName,
        accessLevel: accessLevel
    )
    try emitter.emit(catalog).write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
} catch let error as XCStringsError {
    // `path:line:column: error:` when the location is a source position.
    let isPosition = error.location.split(separator: ":").count == 2 && error.location.allSatisfy { $0.isNumber || $0 == ":" }
    fail(isPosition ? "\(input):\(error.location): error: \(error.message)" : "\(input): error: \(error)")
} catch {
    fail("\(input): error: \(error.localizedDescription)")
}
