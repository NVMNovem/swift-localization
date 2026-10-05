import SwiftLocalization

// Both accessors exist only if the plugin generated both catalogs.
// `Localizable.xcstrings` is Tests/Fixtures/Localizable.xcstrings, which the
// integration test copies next to this file.
let fooBar = LocalizationResolver(catalog: .fooBar)
let localizable = LocalizationResolver(catalog: .localizable)

let count = 3
let files = 1
let lines: [String] = [
    fooBar.string(for: "greeting", locale: "en"),
    "\(LocalizationCatalog.localizable.entries.count) keys",
    localizable.string(for: "cart.title", locale: "nl-BE"),
    localizable.string(for: "\(count) items", locale: "pl"),
    localizable.string(for: "\(files) files in \(count) folders", locale: "en"),
]
print(lines.joined(separator: "\n"))
