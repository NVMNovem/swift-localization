// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-localization",
    products: [
        .library(name: "SwiftLocalization", targets: ["SwiftLocalization"]),
        .plugin(name: "SwiftLocalizationPlugin", targets: ["SwiftLocalizationPlugin"]),
    ],
    targets: [
        // Portable runtime: no Foundation, no JavaScriptKit.
        .target(name: "SwiftLocalization"),

        // `.xcstrings` catalog frontend. Host-side only; not part of the runtime product.
        .target(name: "SwiftLocalizationXCStrings", dependencies: ["SwiftLocalization"]),

        // Deterministic Swift emitter for the neutral catalog model.
        .target(name: "SwiftLocalizationGeneratorCore", dependencies: ["SwiftLocalization"]),

        .executableTarget(
            name: "SwiftLocalizationGenerator",
            dependencies: ["SwiftLocalizationXCStrings", "SwiftLocalizationGeneratorCore"]
        ),
        .plugin(
            name: "SwiftLocalizationPlugin",
            capability: .buildTool(),
            dependencies: ["SwiftLocalizationGenerator"]
        ),

        .testTarget(name: "SwiftLocalizationTests", dependencies: ["SwiftLocalization"]),
        .testTarget(
            name: "SwiftLocalizationXCStringsTests",
            dependencies: ["SwiftLocalization", "SwiftLocalizationXCStrings", "SwiftLocalizationGeneratorCore"]
        ),
        .testTarget(
            name: "SwiftLocalizationPluginTests",
            dependencies: ["SwiftLocalization"],
            plugins: ["SwiftLocalizationPlugin"]
        ),
    ]
)
