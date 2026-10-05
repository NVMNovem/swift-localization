// swift-tools-version: 6.3
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

        // Deterministic Swift emitter for the neutral catalog model,
        // and the generator's command logic, kept out of the executable so
        // that it can be unit tested.
        .target(
            name: "SwiftLocalizationGeneratorCore",
            dependencies: ["SwiftLocalization", "SwiftLocalizationXCStrings"]
        ),

        .executableTarget(
            name: "SwiftLocalizationGenerator",
            dependencies: ["SwiftLocalizationGeneratorCore"]
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
        // Runs the real generator executable and builds the fixture package in
        // Tests/Fixtures with the real plugin. No target of this package applies
        // the plugin itself: that would make every build, including a
        // cross-compiled `--target SwiftLocalization`, build the host generator.
        .testTarget(
            name: "SwiftLocalizationIntegrationTests",
            dependencies: ["SwiftLocalizationGenerator"]
        ),
    ]
)
