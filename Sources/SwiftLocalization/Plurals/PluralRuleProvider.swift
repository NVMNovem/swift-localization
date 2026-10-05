/// A service that selects the plural category of a number in a locale.
///
/// The package ships ``CLDRPluralRules``. A platform adapter may supply its
/// own conformance, for example one backed by JavaScript `Intl.PluralRules`.
public protocol PluralRuleProvider: Sendable {
    func category(
        for operands: PluralOperands,
        type: PluralRuleType,
        locale: LocaleIdentifier
    ) -> PluralCategory
}

/// Plural rules compiled from a pinned release of the Unicode CLDR.
///
/// The rule tables are checked-in generated code; see
/// `Tools/CLDRPluralGenerator`. A locale is matched through its
/// ``LocaleIdentifier/fallbackChain``, and a language CLDR has no rules for
/// uses the root rule, which is always `other`.
public struct CLDRPluralRules: PluralRuleProvider {
    public init() {}

    public func category(
        for operands: PluralOperands,
        type: PluralRuleType,
        locale: LocaleIdentifier
    ) -> PluralCategory {
        let locales: [String]
        let rules: [UInt8]
        switch type {
        case .cardinal: (locales, rules) = (Self.cardinalLocales, Self.cardinalRules)
        case .ordinal: (locales, rules) = (Self.ordinalLocales, Self.ordinalRules)
        }
        for candidate in locale.fallbackChain {
            if let index = Self.index(of: candidate.identifier.lowercased(), in: locales) {
                return Self.evaluate(rule: rules[index], operands)
            }
        }
        return .other
    }

    /// Binary search over lowercased ASCII locale identifiers.
    private static func index(of key: String, in sorted: [String]) -> Int? {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle].utf8.lexicographicallyPrecedes(key.utf8) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < sorted.count && sorted[low] == key ? low : nil
    }
}
