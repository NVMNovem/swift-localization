import SwiftLocalization

// `Foo-Bar.xcstrings` and `Sub/Foo Bar.xcstrings` both map to this accessor,
// so the plugin must fail before this file is compiled.
let catalog = LocalizationCatalog.fooBar
