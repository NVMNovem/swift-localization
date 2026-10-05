import SwiftLocalization
import SwiftLocalizationXCStrings

/// The command line of `SwiftLocalizationGenerator`, without the process
/// boundary: arguments are parsed and catalogs converted here, while reading
/// and writing files is left to the caller.
package struct GeneratorCommand: Equatable, Sendable {
    package struct Job: Equatable, Sendable {
        package var input: String
        package var output: String

        package init(input: String, output: String) {
            self.input = input
            self.output = output
        }
    }

    /// A generated file that is ready to be written.
    package struct Output: Equatable, Sendable {
        package var path: String
        package var contents: String
    }

    /// A diagnostic for standard error. The process exits unsuccessfully.
    package struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        package var message: String

        package init(message: String) {
            self.message = message
        }

        package var description: String { message }
    }

    package enum Action: Equatable, Sendable {
        case help
        case generate(GeneratorCommand)
    }

    package static let usage = """
        Usage: SwiftLocalizationGenerator <catalog.xcstrings> --output <file.swift>
                   [<catalog.xcstrings> --output <file.swift> ...]
                   [--name <property>] [--access-level internal|package|public]

        Catalogs generated together must have distinct accessor names.
        --name overrides the accessor and is only valid with a single catalog.
        """

    /// The catalogs to convert, in command-line order.
    package var jobs: [Job]
    /// The accessor name of each job.
    package var propertyNames: [String]
    package var accessLevel: String

    /// Parses and validates `arguments`, which exclude the executable name.
    ///
    /// Every accessor name is settled here, so an invalid `--name` or two
    /// catalogs that share an accessor fail before any catalog is read.
    package static func parse(_ arguments: [String]) throws(Failure) -> Action {
        var pending: [(input: String, output: String?)] = []
        var explicitName: String?
        var accessLevel = "internal"

        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "-o", "--output":
                guard let path = remaining.popFirst(), let last = pending.indices.last, pending[last].output == nil else {
                    throw Failure(message: "error: --output must follow a catalog and name a file\n" + usage)
                }
                pending[last].output = path
            case "--name":
                guard let value = remaining.popFirst() else {
                    throw Failure(message: "error: --name requires a value\n" + usage)
                }
                explicitName = value
            case "--access-level":
                guard let level = remaining.popFirst(), ["internal", "package", "public"].contains(level) else {
                    throw Failure(message: "error: --access-level must be internal, package, or public\n" + usage)
                }
                accessLevel = level
            case "-h", "--help":
                return .help
            default:
                guard !argument.hasPrefix("-") else {
                    throw Failure(message: "error: unexpected argument '\(argument)'\n" + usage)
                }
                pending.append((argument, nil))
            }
        }
        guard !pending.isEmpty else { throw Failure(message: usage) }

        var jobs: [Job] = []
        for job in pending {
            guard let output = job.output else {
                throw Failure(message: "error: no --output for '\(job.input)'\n" + usage)
            }
            jobs.append(Job(input: job.input, output: output))
        }

        let names: [String]
        if let explicitName {
            guard jobs.count == 1 else {
                throw Failure(message: "error: --name cannot be used with more than one catalog")
            }
            guard SwiftCatalogEmitter.isValidPropertyName(explicitName) else {
                throw Failure(message: "error: --name: \(SwiftCatalogEmitter.NameError.invalidName(explicitName))")
            }
            names = [explicitName]
        } else {
            do {
                names = try SwiftCatalogEmitter.propertyNames(forCatalogs: jobs.map { ($0.input, fileName(of: $0.input)) })
            } catch {
                throw Failure(message: "error: \(error)")
            }
        }
        return .generate(GeneratorCommand(jobs: jobs, propertyNames: names, accessLevel: accessLevel))
    }

    /// Converts every catalog, reading each input with `read`.
    ///
    /// Nothing is returned unless every catalog converts, so a caller that
    /// writes the result never leaves partial output behind.
    package func outputs(read: (String) throws -> String) throws(Failure) -> [Output] {
        var outputs: [Output] = []
        for (job, name) in zip(jobs, propertyNames) {
            let source: String
            do {
                source = try read(job.input)
            } catch {
                throw Failure(message: "\(job.input): error: \(error)")
            }
            do {
                let catalog = try XCStringsDocument(parsing: source).catalog()
                let emitter = try SwiftCatalogEmitter(
                    propertyName: name, sourceFileName: Self.fileName(of: job.input), accessLevel: accessLevel
                )
                outputs.append(Output(path: job.output, contents: emitter.emit(catalog)))
            } catch let error as XCStringsError {
                // `path:line:column: error:` when the location is a source position.
                let isPosition = error.location.split(separator: ":").count == 2
                    && error.location.allSatisfy { $0.isNumber || $0 == ":" }
                throw Failure(message: isPosition
                    ? "\(job.input):\(error.location): error: \(error.message)"
                    : "\(job.input): error: \(error)")
            } catch {
                throw Failure(message: "\(job.input): error: \(error)")
            }
        }
        return outputs
    }

    /// The last path component, without Foundation.
    static func fileName(of path: String) -> String {
        let components = path.split(omittingEmptySubsequences: true) { character in
            #if os(Windows)
            character == "/" || character == "\\"
            #else
            character == "/"
            #endif
        }
        return components.last.map(String.init) ?? path
    }
}
