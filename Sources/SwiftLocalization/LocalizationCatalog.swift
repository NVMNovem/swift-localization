/// A format-neutral table of localized strings.
///
/// Catalog frontends such as the `.xcstrings` reader convert their format to
/// this model; the resolver knows nothing about where a catalog came from.
public struct LocalizationCatalog: Hashable, Sendable {
    /// The language the keys' default values are written in.
    public var sourceLanguage: LocaleIdentifier
    /// The entries, by key.
    public var entries: [String: Entry]

    public init(sourceLanguage: LocaleIdentifier, entries: [String: Entry] = [:]) {
        self.sourceLanguage = sourceLanguage
        self.entries = entries
    }

    /// The localizations of one key.
    public struct Entry: Hashable, Sendable {
        public var localizations: [LocaleIdentifier: Localization]

        public init(localizations: [LocaleIdentifier: Localization] = [:]) {
            self.localizations = localizations
        }
    }

    /// One key in one locale.
    public struct Localization: Hashable, Sendable {
        /// The format string, possibly varied by plural category or device.
        public var variation: Variation
        /// Named substitutions referenced from a format string as `%#@name@`.
        public var substitutions: [String: Substitution]

        public init(variation: Variation, substitutions: [String: Substitution] = [:]) {
            self.variation = variation
            self.substitutions = substitutions
        }
    }

    /// A format string or a choice between format strings.
    public indirect enum Variation: Hashable, Sendable {
        /// A format string.
        case string(String)
        /// A choice by the plural category of a numeric argument. A complete
        /// variation has an `other` case.
        case plural(PluralRuleType, [PluralCategory: Variation])
        /// A choice by device category, with `other` as the default case.
        case device([String: Variation])
    }

    /// A named part of a format string that varies by one argument.
    public struct Substitution: Hashable, Sendable {
        /// The 1-based position of the argument that drives the substitution.
        /// When `nil`, the substitution takes the next unnumbered argument.
        public var argumentIndex: Int?
        /// The format specifier of that argument without its `%`, such as
        /// `lld`. Inside the substitution's strings it is spelled `%arg`.
        public var formatSpecifier: String
        public var variation: Variation

        public init(argumentIndex: Int? = nil, formatSpecifier: String, variation: Variation) {
            self.argumentIndex = argumentIndex
            self.formatSpecifier = formatSpecifier
            self.variation = variation
        }
    }
}
