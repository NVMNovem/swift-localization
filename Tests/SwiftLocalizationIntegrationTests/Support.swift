import Foundation

struct IntegrationError: Error, CustomStringConvertible {
    var description: String
}

/// The repository under test.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A directory that is removed when the value is released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-localization-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        // The canonical path, which is how tools report files in it.
        guard let resolved = realpath(created.path, nil) else {
            throw IntegrationError(description: "cannot resolve \(created.path)")
        }
        defer { free(resolved) }
        url = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }

    @discardableResult
    func write(_ contents: String, to name: String) throws -> URL {
        let destination = file(name)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: destination)
        return destination
    }
}

struct ProcessResult {
    var status: Int32
    /// Standard output and standard error, interleaved.
    var output: String
}

func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

/// The directory that holds the binary these tests were compiled into.
private func testBinary() throws -> URL {
    var info = Dl_info()
    guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else {
        throw IntegrationError(description: "cannot locate the test binary")
    }
    return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
}

/// The generator executable SwiftPM built as a dependency of this test
/// target. It is found next to the test binary, wherever the build
/// directory is.
func generatorExecutable() throws -> URL {
    var directory = try testBinary().deletingLastPathComponent()
    for _ in 0..<6 {
        let candidate = directory.appendingPathComponent("SwiftLocalizationGenerator")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
           FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        directory.deleteLastPathComponent()
    }
    throw IntegrationError(description: "SwiftLocalizationGenerator was not built next to the test binary")
}

/// The `swift` of the toolchain that is running these tests, so that a nested
/// build never mixes toolchains. `swift test` runs tests through a helper
/// inside the toolchain; when that is not the case, `swift` is taken from
/// `PATH`.
func swiftExecutable() -> (url: URL, prefix: [String]) {
    var directory = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).resolvingSymlinksInPath()
    while directory.pathComponents.count > 1 {
        directory.deleteLastPathComponent()
        let candidate = directory.appendingPathComponent("usr/bin/swift")
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return (candidate, []) }
    }
    return (URL(fileURLWithPath: "/usr/bin/env"), ["swift"])
}

/// A minimal catalog in Xcode's layout with one English string.
func catalog(greeting: String) -> String {
    """
    {
      "sourceLanguage" : "en",
      "strings" : {
        "greeting" : {
          "localizations" : {
            "en" : {
              "stringUnit" : {
                "state" : "translated",
                "value" : "\(greeting)"
              }
            }
          }
        }
      },
      "version" : "1.0"
    }
    """
}

/// The names of the Swift files anywhere below `directory`, sorted.
func swiftFiles(in directory: URL) throws -> [String] {
    try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".swift") }
        .map { URL(fileURLWithPath: $0).lastPathComponent }
        .sorted()
}
