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

extension SwiftLocalizationPlugin {
    /// One command generates every catalog of the target, so the generator
    /// sees them together and can reject two catalogs that would get the same
    /// `LocalizationCatalog` accessor. Accessor names are derived in the
    /// generator only; the plugin does not reimplement that rule.
    func buildCommands(for files: [URL], in workDirectory: URL, with generator: URL) throws -> [Command] {
        let catalogs = files
            .filter { $0.pathExtension == "xcstrings" }
            .sorted { $0.path < $1.path }
        guard !catalogs.isEmpty else { return [] }

        // Output file names only have to be unique; they are not the accessors.
        var usedNames: Set<String> = []
        var arguments: [String] = []
        var outputs: [URL] = []
        for catalog in catalogs {
            let stem = catalog.deletingPathExtension().lastPathComponent
            var name = stem
            var suffix = 2
            while !usedNames.insert(name).inserted {
                name = "\(stem)-\(suffix)"
                suffix += 1
            }
            let output = workDirectory.appendingPathComponent(name + "+LocalizationCatalog.swift")
            arguments += [catalog.path, "--output", output.path]
            outputs.append(output)
        }
        return [
            .buildCommand(
                displayName: "Generating localization catalogs from "
                    + catalogs.map(\.lastPathComponent).joined(separator: ", "),
                executable: generator,
                arguments: arguments,
                inputFiles: catalogs,
                outputFiles: outputs
            ),
        ]
    }
}
