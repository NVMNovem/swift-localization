import Foundation
import SwiftLocalizationGeneratorCore

// The process boundary of the generator: arguments in, files and an exit
// status out. Everything else is `GeneratorCommand`. Foundation is used here
// for file access only; it does not reach the runtime library.

/// A file-system error as a diagnostic.
struct FileError: Error, CustomStringConvertible {
    var description: String
}

func fail(_ failure: GeneratorCommand.Failure) -> Never {
    FileHandle.standardError.write(Data((failure.message + "\n").utf8))
    exit(1)
}

do {
    switch try GeneratorCommand.parse(Array(CommandLine.arguments.dropFirst())) {
    case .help:
        print(GeneratorCommand.usage)
    case .generate(let command):
        let outputs = try command.outputs { path in
            do {
                return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            } catch {
                throw FileError(description: error.localizedDescription)
            }
        }
        for output in outputs {
            do {
                try output.contents.write(to: URL(fileURLWithPath: output.path), atomically: true, encoding: .utf8)
            } catch {
                fail(.init(message: "\(output.path): error: \(error.localizedDescription)"))
            }
        }
    }
} catch {
    fail(error)
}
