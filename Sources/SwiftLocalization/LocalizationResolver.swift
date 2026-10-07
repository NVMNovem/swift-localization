/// A service that turns a locale-neutral decimal number into display text.
///
/// `decimal` is an optional `-`, ASCII digits, and an optional `.` followed by
/// ASCII digits. A platform adapter can map it to localized digits, grouping,
/// and decimal separators.
public protocol LocalizedNumberFormatter: Sendable {
    func string(fromDecimal decimal: String, locale: LocaleIdentifier) -> String
}

/// The portable default formatter: numbers are displayed as their
/// locale-neutral decimal text, without grouping or digit substitution.
public struct VerbatimNumberFormatter: LocalizedNumberFormatter {
    public init() {}

    public func string(fromDecimal decimal: String, locale: LocaleIdentifier) -> String {
        decimal
    }
}

/// Why a resource could not be resolved.
public struct LocalizationError: Error, Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// The catalog has no entry for the key.
        case missingKey
        /// The entry has no localization for the locale, its fallbacks, or the
        /// catalog's source language.
        case missingLocale
        /// A variation is incomplete or refers to an unknown substitution.
        case malformedVariation(String)
        /// A plural variation has no numeric argument to select with.
        case missingPluralArgument
        /// The format string refers to an argument that was not supplied.
        /// `position` is 1-based.
        case missingArgument(position: Int)
        /// The argument cannot be formatted with the specifier.
        case incompatibleArgument(position: Int, specifier: String)
        /// The format string uses a specifier outside the supported surface.
        case unsupportedFormat(specifier: String)
    }

    public var key: String
    public var locale: LocaleIdentifier
    public var reason: Reason

    public init(key: String, locale: LocaleIdentifier, reason: Reason) {
        self.key = key
        self.locale = locale
        self.reason = reason
    }
}

/// Resolves resources against a catalog for a locale.
///
/// Lookup order is the requested locale's ``LocaleIdentifier/fallbackChain``,
/// then the chain of each of ``fallbackLocales`` in order, then the chain of
/// the catalog's source language. Plural categories are selected with the
/// rules of the locale whose localization matched; numbers are formatted for
/// the requested locale.
public struct LocalizationResolver: Sendable {
    public var catalog: LocalizationCatalog
    // The services are stored as closures over concrete types, not as
    // protocol existentials, so that the resolver compiles for Embedded Swift.
    var pluralCategory: @Sendable (PluralOperands, PluralRuleType, LocaleIdentifier) -> PluralCategory
    var localizedNumber: @Sendable (String, LocaleIdentifier) -> String
    /// Locales consulted after the requested locale and before the catalog's
    /// source language.
    public var fallbackLocales: [LocaleIdentifier]
    /// The device category used for device variations, such as `iphone` or
    /// `mac`. When `nil` or unmatched, a device variation uses its `other`
    /// case.
    public var deviceCategory: String?

    public init(
        catalog: LocalizationCatalog,
        pluralRules: some PluralRuleProvider = CLDRPluralRules(),
        numberFormatter: some LocalizedNumberFormatter = VerbatimNumberFormatter(),
        fallbackLocales: [LocaleIdentifier] = [],
        deviceCategory: String? = nil
    ) {
        self.catalog = catalog
        self.pluralCategory = { pluralRules.category(for: $0, type: $1, locale: $2) }
        self.localizedNumber = { numberFormatter.string(fromDecimal: $0, locale: $1) }
        self.fallbackLocales = fallbackLocales
        self.deviceCategory = deviceCategory
    }

    /// Replaces the service that selects plural categories.
    public mutating func setPluralRules(_ pluralRules: some PluralRuleProvider) {
        pluralCategory = { pluralRules.category(for: $0, type: $1, locale: $2) }
    }

    /// Replaces the service that turns decimal numbers into display text.
    public mutating func setNumberFormatter(_ numberFormatter: some LocalizedNumberFormatter) {
        localizedNumber = { numberFormatter.string(fromDecimal: $0, locale: $1) }
    }

    /// Resolves `resource`, falling back to its default value.
    ///
    /// When ``resolve(_:locale:)`` fails for any reason, the default value is
    /// formatted with the catalog's source-language rules. If that fails too,
    /// the unformatted default value is returned.
    public func string(for resource: LocalizedResource, locale: LocaleIdentifier) -> String {
        if let resolved = try? resolve(resource, locale: locale) { return resolved }
        let value = resource.defaultValue
        guard !value.arguments.isEmpty else { return value.key }
        let renderer = Renderer(
            resolver: self, key: resource.key, locale: locale, pluralLocale: catalog.sourceLanguage,
            arguments: value.arguments, substitutions: [:]
        )
        return (try? renderer.render(value.key, own: nil, depth: 0)) ?? value.key
    }

    /// Resolves `resource` from the catalog, or throws the reason it could not
    /// be resolved.
    ///
    /// A localization is treated as a format string only when the resource has
    /// arguments or the localization has substitutions; otherwise it is
    /// returned verbatim.
    public func resolve(_ resource: LocalizedResource, locale: LocaleIdentifier) throws(LocalizationError) -> String {
        guard let entry = catalog.entries[resource.key] else {
            throw LocalizationError(key: resource.key, locale: locale, reason: .missingKey)
        }
        var match: (locale: LocaleIdentifier, localization: LocalizationCatalog.Localization)?
        search: for root in [locale] + fallbackLocales + [catalog.sourceLanguage] {
            for candidate in root.fallbackChain {
                if let localization = entry.localizations[candidate] {
                    match = (candidate, localization)
                    break search
                }
            }
        }
        guard let match else {
            throw LocalizationError(key: resource.key, locale: locale, reason: .missingLocale)
        }

        let arguments = resource.defaultValue.arguments
        let renderer = Renderer(
            resolver: self, key: resource.key, locale: locale, pluralLocale: match.locale,
            arguments: arguments, substitutions: match.localization.substitutions
        )
        let pluralIndex = arguments.firstIndex { argument in
            if case .string = argument { false } else { true }
        }
        let precision = pluralIndex.map { Renderer.floatPrecision(ofArgument: $0, in: match.localization.variation) } ?? 6
        let format = try renderer.select(match.localization.variation, argumentIndex: pluralIndex, precision: precision)
        if arguments.isEmpty && match.localization.substitutions.isEmpty { return format }
        return try renderer.render(format, own: nil, depth: 0)
    }
}

private struct Renderer {
    typealias Variation = LocalizationCatalog.Variation

    let resolver: LocalizationResolver
    let key: String
    /// The requested locale, used for number formatting.
    let locale: LocaleIdentifier
    /// The locale of the matched localization, used for plural rules.
    let pluralLocale: LocaleIdentifier
    let arguments: [LocalizationArgument]
    let substitutions: [String: LocalizationCatalog.Substitution]

    func error(_ reason: LocalizationError.Reason) -> LocalizationError {
        LocalizationError(key: key, locale: locale, reason: reason)
    }

    func parse(_ format: String, allowsSubstitutionArgument: Bool) throws(LocalizationError) -> [FormatString.Segment] {
        do {
            return try FormatString.parse(format, allowsSubstitutionArgument: allowsSubstitutionArgument)
        } catch {
            throw self.error(.unsupportedFormat(specifier: error.specifier))
        }
    }

    /// Reduces a variation to one format string.
    func select(_ variation: Variation, argumentIndex: Int?, precision: Int) throws(LocalizationError) -> String {
        switch variation {
        case .string(let format):
            return format
        case .device(let cases):
            guard let next = resolver.deviceCategory.flatMap({ cases[$0] }) ?? cases["other"] else {
                throw error(.malformedVariation("device variation has no \"other\" case"))
            }
            return try select(next, argumentIndex: argumentIndex, precision: precision)
        case .plural(let type, let cases):
            guard let argumentIndex, arguments.indices.contains(argumentIndex),
                  let operands = Self.operands(of: arguments[argumentIndex], precision: precision)
            else { throw error(.missingPluralArgument) }
            let category = resolver.pluralCategory(operands, type, pluralLocale)
            guard let next = cases[category] ?? cases[.other] else {
                throw error(.malformedVariation("plural variation has no \"other\" case"))
            }
            return try select(next, argumentIndex: argumentIndex, precision: precision)
        }
    }

    /// Formats `format`. Inside a substitution, `own` is the substitution's
    /// argument: `%arg` and unnumbered specifiers refer to it.
    func render(
        _ format: String,
        own: (index: Int, conversion: FormatString.Conversion)?,
        depth: Int
    ) throws(LocalizationError) -> String {
        guard depth < 8 else { throw error(.malformedVariation("substitutions are nested too deeply")) }
        var output = ""
        var nextIndex = 0
        for segment in try parse(format, allowsSubstitutionArgument: own != nil) {
            switch segment {
            case .literal(let text):
                output += text

            case .argument(let position, var conversion, let specifier):
                let index: Int
                if conversion == .substitutionArgument, let own {
                    index = own.index
                    conversion = own.conversion
                } else if let position {
                    index = position - 1
                } else if let own {
                    index = own.index
                } else {
                    index = nextIndex
                    nextIndex += 1
                }
                output += try formatted(index: index, conversion: conversion, specifier: specifier)

            case .substitution(let name, let position):
                guard let substitution = substitutions[name] else {
                    throw error(.malformedVariation("unknown substitution \"\(name)\""))
                }
                let index: Int
                if let explicit = substitution.argumentIndex ?? position {
                    index = explicit - 1
                } else {
                    index = nextIndex
                    nextIndex += 1
                }
                let specifier = "%" + substitution.formatSpecifier
                let parsed = try parse(specifier, allowsSubstitutionArgument: false)
                guard parsed.count == 1, case .argument(nil, let conversion, _) = parsed[0], conversion != .object else {
                    throw error(.unsupportedFormat(specifier: specifier))
                }
                var precision = 6
                if case .float(let explicit?) = conversion { precision = explicit }
                let text = try select(substitution.variation, argumentIndex: index, precision: precision)
                output += try render(text, own: (index, conversion), depth: depth + 1)
            }
        }
        return output
    }

    func formatted(index: Int, conversion: FormatString.Conversion, specifier: String) throws(LocalizationError) -> String {
        guard arguments.indices.contains(index) else {
            throw error(.missingArgument(position: index + 1))
        }
        let decimal: String
        switch (conversion, arguments[index]) {
        case (.object, .string(let value)):
            return value
        case (.object, .integer(let value)), (.signed, .integer(let value)), (.unsigned, .integer(let value)):
            decimal = String(value)
        case (.object, .unsignedInteger(let value)), (.signed, .unsignedInteger(let value)),
             (.unsigned, .unsignedInteger(let value)):
            decimal = String(value)
        case (.object, .floatingPoint(let value)):
            guard let text = DecimalText.fixed(value, precision: nil) else { return value.description }
            decimal = text
        case (.float(let precision), .floatingPoint(let value)):
            guard let text = DecimalText.fixed(value, precision: precision ?? 6) else { return value.description }
            decimal = text
        case (.float(let precision), .integer(let value)):
            decimal = Self.padded(String(value), precision: precision ?? 6)
        case (.float(let precision), .unsignedInteger(let value)):
            decimal = Self.padded(String(value), precision: precision ?? 6)
        default:
            throw error(.incompatibleArgument(position: index + 1, specifier: specifier))
        }
        return resolver.localizedNumber(decimal, locale)
    }

    static func padded(_ integer: String, precision: Int) -> String {
        precision > 0 ? integer + "." + String(repeating: "0", count: precision) : integer
    }

    static func operands(of argument: LocalizationArgument, precision: Int) -> PluralOperands? {
        switch argument {
        case .string: nil
        case .integer(let value): PluralOperands(value)
        case .unsignedInteger(let value): PluralOperands(value)
        case .floatingPoint(let value): PluralOperands(value, fractionDigits: precision)
        }
    }

    /// The number of fraction digits a top-level variation displays for the
    /// argument at `index`, read from the variation's default branch.
    static func floatPrecision(ofArgument index: Int, in variation: Variation) -> Int {
        var current = variation
        while true {
            switch current {
            case .string(let format):
                guard let segments = try? FormatString.parse(format) else { return 6 }
                var nextIndex = 0
                for case .argument(let position, let conversion, _) in segments {
                    let argumentIndex = position.map { $0 - 1 } ?? nextIndex
                    if position == nil { nextIndex += 1 }
                    if argumentIndex == index, case .float(let precision?) = conversion { return precision }
                }
                return 6
            case .plural(_, let cases):
                guard let next = cases[.other] else { return 6 }
                current = next
            case .device(let cases):
                guard let next = cases["other"] else { return 6 }
                current = next
            }
        }
    }
}
