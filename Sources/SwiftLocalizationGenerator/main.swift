import Foundation
import SwiftLocalizationGeneratorCore
import SwiftLocalizationXCStrings

// Converts `.xcstrings` catalogs to Swift source. Foundation is used here for
// file access only; it does not reach the runtime library.

let usage = """
    Usage: SwiftLocalizationGenerator <catalog.xcstrings> --output <file.swift>
               [<catalog.xcstrings> --output <file.swift> ...]
               [--name <property>] [--access-level internal|package|public]

    Catalogs generated together must have distinct accessor names.
    --name overrides the accessor and is only valid with a single catalog.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var jobs: [(input: String, output: String?)] = []
var explicitName: String?
var accessLevel = "internal"

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "-o", "--output":
        guard let path = arguments.popFirst(), let last = jobs.indices.last, jobs[last].output == nil else {
            fail("error: --output must follow a catalog and name a file\n" + usage)
        }
        jobs[last].output = path
    case "--name":
        guard let value = arguments.popFirst() else { fail("error: --name requires a value\n" + usage) }
        explicitName = value
    case "--access-level":
        guard let level = arguments.popFirst(), ["internal", "package", "public"].contains(level) else {
            fail("error: --access-level must be internal, package, or public\n" + usage)
        }
        accessLevel = level
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard !argument.hasPrefix("-") else { fail("error: unexpected argument '\(argument)'\n" + usage) }
        jobs.append((argument, nil))
    }
}
guard !jobs.isEmpty else { fail(usage) }
for job in jobs where job.output == nil {
    fail("error: no --output for '\(job.input)'\n" + usage)
}

// Settle every accessor name before anything is written.
let fileNames = jobs.map { URL(fileURLWithPath: $0.input).lastPathComponent }
let names: [String]
do {
    if let explicitName {
        guard jobs.count == 1 else { fail("error: --name cannot be used with more than one catalog") }
        guard SwiftCatalogEmitter.isValidPropertyName(explicitName) else {
            throw SwiftCatalogEmitter.NameError.invalidName(explicitName)
        }
        names = [explicitName]
    } else {
        names = try SwiftCatalogEmitter.propertyNames(forCatalogs: zip(jobs, fileNames).map { ($0.input, $1) })
    }
} catch {
    fail("error: \(error)")
}

for (index, job) in jobs.enumerated() {
    do {
        let source = try String(contentsOf: URL(fileURLWithPath: job.input), encoding: .utf8)
        let catalog = try XCStringsDocument(parsing: source).catalog()
        let emitter = try SwiftCatalogEmitter(
            propertyName: names[index], sourceFileName: fileNames[index], accessLevel: accessLevel
        )
        try emitter.emit(catalog).write(to: URL(fileURLWithPath: job.output!), atomically: true, encoding: .utf8)
    } catch let error as XCStringsError {
        // `path:line:column: error:` when the location is a source position.
        let isPosition = error.location.split(separator: ":").count == 2
            && error.location.allSatisfy { $0.isNumber || $0 == ":" }
        fail(isPosition ? "\(job.input):\(error.location): error: \(error.message)" : "\(job.input): error: \(error)")
    } catch let error as SwiftCatalogEmitter.NameError {
        fail("\(job.input): error: \(error)")
    } catch {
        fail("\(job.input): error: \(error.localizedDescription)")
    }
}
