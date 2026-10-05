// swift-tools-version: 6.0

import PackageDescription

// Maintainer-only tool. It is deliberately a separate package so that it never
// appears in the dependency graph or build of `swift-localization` consumers.
let package = Package(
    name: "CLDRPluralGenerator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CLDRPluralGenerator"),
    ]
)
