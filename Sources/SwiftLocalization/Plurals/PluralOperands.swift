/// A CLDR plural category.
public enum PluralCategory: String, Hashable, Sendable, CaseIterable {
    case zero, one, two, few, many, other
}

/// Which CLDR plural rule set applies to a number.
public enum PluralRuleType: String, Hashable, Sendable, CaseIterable {
    /// "1 item", "2 items".
    case cardinal
    /// "1st", "2nd", "3rd".
    case ordinal
}

/// The plural operands of a number as defined by Unicode TR35.
///
/// Operands describe the number as it is displayed, so `1`, `1.0`, and `1.00`
/// are three different values: they share `i` but differ in `v`.
public struct PluralOperands: Hashable, Sendable {
    /// The integer digits of the absolute value.
    public var i: UInt64
    /// The number of visible fraction digits, with trailing zeros.
    public var v: Int
    /// The number of visible fraction digits, without trailing zeros.
    public var w: Int
    /// The visible fraction digits, with trailing zeros, as an integer.
    public var f: UInt64
    /// The visible fraction digits, without trailing zeros, as an integer.
    public var t: UInt64
    /// The compact decimal exponent (`c`, also spelled `e`).
    public var c: Int

    public init(i: UInt64, v: Int = 0, w: Int = 0, f: UInt64 = 0, t: UInt64 = 0, c: Int = 0) {
        self.i = i
        self.v = v
        self.w = w
        self.f = f
        self.t = t
        self.c = c
    }

    /// The operands of an integer displayed without fraction digits.
    ///
    /// Magnitudes above `UInt64.max` are clamped.
    public init(_ value: some BinaryInteger) {
        self.init(i: UInt64(clamping: value.magnitude))
    }

    /// The operands of a locale-neutral decimal string.
    ///
    /// The accepted form is an optional sign, ASCII digits, an optional `.`
    /// followed by fraction digits, and an optional compact exponent written
    /// `c` or `e` (`1.2c6`). Returns `nil` for anything else.
    ///
    /// At most 18 integer and 18 fraction digits are significant. Longer
    /// integer parts keep their low digits and stay larger than any value a
    /// plural rule compares against.
    public init?(decimal: String) {
        var bytes = decimal.utf8[...]
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        func takeDigits() -> [UInt8] {
            var digits: [UInt8] = []
            while let byte = bytes.first, isDigit(byte) {
                digits.append(byte - 0x30)
                bytes.removeFirst()
            }
            return digits
        }

        if let sign = bytes.first, sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
            bytes.removeFirst()
        }
        var integer = takeDigits()
        guard !integer.isEmpty else { return nil }
        var fraction: [UInt8] = []
        if bytes.first == UInt8(ascii: ".") {
            bytes.removeFirst()
            fraction = takeDigits()
            guard !fraction.isEmpty else { return nil }
        }
        var exponent = 0
        if let marker = bytes.first, marker == UInt8(ascii: "c") || marker == UInt8(ascii: "e") {
            bytes.removeFirst()
            let digits = takeDigits()
            guard !digits.isEmpty, digits.count <= 3 else { return nil }
            exponent = digits.reduce(0) { $0 * 10 + Int($1) }
        }
        guard bytes.isEmpty else { return nil }

        // Shift the decimal point right by the compact exponent.
        let moved = min(exponent, fraction.count)
        integer += fraction.prefix(moved)
        fraction.removeFirst(moved)
        integer += [UInt8](repeating: 0, count: exponent - moved)

        let significant = integer.drop { $0 == 0 }
        var i = significant.suffix(18).reduce(UInt64(0)) { $0 * 10 + UInt64($1) }
        if significant.count > 18 { i += 1_000_000_000_000_000_000 }

        fraction = Array(fraction.prefix(18))
        var trimmed = fraction[...]
        while trimmed.last == 0 { trimmed.removeLast() }

        self.init(
            i: i,
            v: fraction.count,
            w: trimmed.count,
            f: fraction.reduce(UInt64(0)) { $0 * 10 + UInt64($1) },
            t: trimmed.reduce(UInt64(0)) { $0 * 10 + UInt64($1) },
            c: exponent
        )
    }

    /// The operands of `value` displayed with exactly `fractionDigits` fraction
    /// digits. Returns `nil` when `value` is not finite.
    public init?(_ value: Double, fractionDigits: Int) {
        guard let text = DecimalText.fixed(value, precision: max(0, fractionDigits)) else { return nil }
        self.init(decimal: text)
    }
}
