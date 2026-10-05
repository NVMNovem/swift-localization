/// A BCP 47 language tag in its normalized form.
///
/// Normalization is syntactic: subtags are separated with `-`, the language is
/// lowercased, the script is title-cased, the region is uppercased, and an
/// extended-language subtag replaces its prefix (`zh-yue` becomes `yue`).
/// Deprecated-subtag aliases and likely-subtag inference are not applied, so
/// `iw` is not rewritten to `he` and `zh-TW` does not imply `zh-Hant`.
public struct LocaleIdentifier: Hashable, Sendable {
    /// The primary language subtag, lowercased. `und` when undetermined.
    public let language: String
    /// The four-letter script subtag in title case.
    public let script: String?
    /// The two-letter (uppercased) or three-digit region subtag.
    public let region: String?
    /// Variant subtags, lowercased, in source order.
    public let variants: [String]
    /// Extension and private-use subtags, lowercased, in source order.
    public let extensions: [String]

    /// The undetermined locale, `und`.
    public static let undetermined = LocaleIdentifier(
        language: "und", script: nil, region: nil, variants: [], extensions: []
    )

    init(language: String, script: String?, region: String?, variants: [String], extensions: [String]) {
        self.language = language
        self.script = script
        self.region = region
        self.variants = variants
        self.extensions = extensions
    }

    /// Normalizes `identifier`, falling back to ``undetermined`` when it is not
    /// a well-formed language tag.
    public init(_ identifier: String) {
        self = LocaleIdentifier(validating: identifier) ?? .undetermined
    }

    /// Normalizes `identifier`, or returns `nil` when it is not a well-formed
    /// language tag.
    ///
    /// `_` is accepted as a separator and a POSIX codeset or modifier suffix
    /// (`.UTF-8`, `@euro`) is ignored. Grandfathered and private-use-only tags
    /// are rejected.
    public init?(validating identifier: String) {
        var text = Substring(identifier)
        if let end = text.firstIndex(where: { $0 == "." || $0 == "@" }) {
            text = text[..<end]
        }
        let subtags = text.split(omittingEmptySubsequences: false) { $0 == "-" || $0 == "_" }
            .map { String($0).lowercased() }
        for subtag in subtags {
            guard (1...8).contains(subtag.utf8.count), subtag.utf8.allSatisfy(Self.isAlphanumeric) else {
                return nil
            }
        }

        var index = 0
        func peek() -> String? { index < subtags.count ? subtags[index] : nil }

        guard let first = peek(), first.utf8.allSatisfy(Self.isLetter),
              (2...3).contains(first.utf8.count) || (5...8).contains(first.utf8.count)
        else { return nil }
        var language = first
        index += 1

        // Extended language subtags: the canonical form keeps only the extlang.
        var extendedLanguages = 0
        while extendedLanguages < 3, first.utf8.count <= 3,
              let next = peek(), next.utf8.count == 3, next.utf8.allSatisfy(Self.isLetter) {
            if extendedLanguages == 0 { language = next }
            extendedLanguages += 1
            index += 1
        }

        var script: String?
        if let next = peek(), next.utf8.count == 4, next.utf8.allSatisfy(Self.isLetter) {
            script = next.prefix(1).uppercased() + next.dropFirst()
            index += 1
        }

        var region: String?
        if let next = peek(),
           (next.utf8.count == 2 && next.utf8.allSatisfy(Self.isLetter))
            || (next.utf8.count == 3 && next.utf8.allSatisfy(Self.isDigit)) {
            region = next.uppercased()
            index += 1
        }

        var variants: [String] = []
        while let next = peek(),
              (5...8).contains(next.utf8.count)
                || (next.utf8.count == 4 && Self.isDigit(next.utf8.first!)) {
            guard !variants.contains(next) else { return nil }
            variants.append(next)
            index += 1
        }

        var extensions: [String] = []
        while let singleton = peek() {
            guard singleton.utf8.count == 1 else { return nil }
            let minimumLength = singleton == "x" ? 1 : 2
            extensions.append(singleton)
            index += 1
            var count = 0
            while let next = peek(), next.utf8.count >= minimumLength {
                extensions.append(next)
                count += 1
                index += 1
            }
            guard count > 0 else { return nil }
            if singleton == "x" { break }
        }
        guard index == subtags.count else { return nil }

        self.init(language: language, script: script, region: region, variants: variants, extensions: extensions)
    }

    /// The normalized tag, for example `zh-Hant-TW`.
    public var identifier: String {
        var parts = [language]
        if let script { parts.append(script) }
        if let region { parts.append(region) }
        parts += variants
        parts += extensions
        return parts.joined(separator: "-")
    }

    /// The locales consulted for this locale, most specific first.
    ///
    /// The chain is produced by truncation only: the full tag, then without
    /// extensions, then without variants, then `language-script`,
    /// `language-region`, and finally the bare language. For `zh-Hant-TW` that
    /// is `zh-Hant-TW`, `zh-Hant`, `zh-TW`, `zh`.
    public var fallbackChain: [LocaleIdentifier] {
        var chain: [LocaleIdentifier] = []
        func add(script: String?, region: String?, variants: [String], extensions: [String]) {
            let candidate = LocaleIdentifier(
                language: language, script: script, region: region, variants: variants, extensions: extensions
            )
            if !chain.contains(candidate) { chain.append(candidate) }
        }
        add(script: script, region: region, variants: variants, extensions: extensions)
        add(script: script, region: region, variants: variants, extensions: [])
        add(script: script, region: region, variants: [], extensions: [])
        add(script: script, region: nil, variants: [], extensions: [])
        add(script: nil, region: region, variants: [], extensions: [])
        add(script: nil, region: nil, variants: [], extensions: [])
        return chain
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        isLetter(byte) || isDigit(byte)
    }
}

extension LocaleIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension LocaleIdentifier: CustomStringConvertible {
    public var description: String { identifier }
}
