import PackagePlugin
import struct Foundation.URL

/// Generates a Swift catalog for every `.xcstrings` file of a target.
///
/// The catalogs are read-only inputs: output is written to the plugin work
/// directory only.
@main
struct SwiftLocalizationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceFiles = target.sourceModule?.sourceFiles else { return [] }
        return try buildCommands(
            for: sourceFiles.map(\.url),
            in: context.pluginWorkDirectoryURL,
            with: context.tool(named: "SwiftLocalizationGenerator").url
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLocalizationPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try buildCommands(
            for: target.inputFiles.map(\.url),
            in: context.pluginWorkDirectoryURL,
            with: context.tool(named: "SwiftLocalizationGenerator").url
        )
    }
}
#endif

struct DuplicateCatalogName: Error, CustomStringConvertible {
    var name: String

    var description: String {
        "more than one string catalog is named '\(name)'; catalog names must be unique within a target"
    }
}

extension SwiftLocalizationPlugin {
    func buildCommands(for files: [URL], in workDirectory: URL, with generator: URL) throws -> [Command] {
        let catalogs = files
            .filter { $0.pathExtension == "xcstrings" }
            .sorted { $0.path < $1.path }
        var names: Set<String> = []
        return try catalogs.map { catalog in
            let name = catalog.deletingPathExtension().lastPathComponent
            guard names.insert(name).inserted else { throw DuplicateCatalogName(name: catalog.lastPathComponent) }
            let output = workDirectory.appendingPathComponent(name + "+LocalizationCatalog.swift")
            return .buildCommand(
                displayName: "Generating \(output.lastPathComponent) from \(catalog.lastPathComponent)",
                executable: generator,
                arguments: [catalog.path, "--output", output.path],
                inputFiles: [catalog],
                outputFiles: [output]
            )
        }
    }
}
