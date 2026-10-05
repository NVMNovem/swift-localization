/// Locale-neutral decimal rendering of numbers.
///
/// The output grammar is an optional `-`, ASCII digits, and an optional `.`
/// followed by ASCII digits. It is the input contract of
/// ``LocalizedNumberFormatter`` and of ``PluralOperands/init(decimal:)``.
enum DecimalText {
    /// Renders `value` in positional notation, or returns `nil` when it is not
    /// finite.
    ///
    /// With a `precision`, the shortest round-trip representation of `value`
    /// is rounded half-to-even to that many fraction digits. Without one, the
    /// shortest round-trip representation is returned unrounded.
    static func fixed(_ value: Double, precision: Int?) -> String? {
        guard value.isFinite else { return nil }

        // `description` is "123.456", "1e-05", or "1.5e+20".
        var mantissa = value.magnitude.description[...]
        var exponent = 0
        if let marker = mantissa.firstIndex(of: "e") {
            exponent = Int(mantissa[mantissa.index(after: marker)...]) ?? 0
            mantissa = mantissa[..<marker]
        }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var integer = parts[0].utf8.map { $0 - 0x30 }
        var fraction = parts.count > 1 ? parts[1].utf8.map { $0 - 0x30 } : []

        if exponent > 0 {
            let moved = min(exponent, fraction.count)
            integer += fraction.prefix(moved)
            fraction.removeFirst(moved)
            integer += [UInt8](repeating: 0, count: exponent - moved)
        } else if exponent < 0 {
            let moved = min(-exponent, integer.count)
            fraction = [UInt8](repeating: 0, count: -exponent - moved) + integer.suffix(moved) + fraction
            integer.removeLast(moved)
        }

        if let precision {
            if fraction.count > precision {
                let cut = fraction[precision]
                let hasRemainder = fraction[(precision + 1)...].contains { $0 != 0 }
                let lastKept = precision > 0 ? fraction[precision - 1] : (integer.last ?? 0)
                let roundsUp = cut > 5 || (cut == 5 && (hasRemainder || lastKept % 2 == 1))
                var digits = integer + fraction.prefix(precision)
                if roundsUp {
                    var position = digits.count - 1
                    while position >= 0, digits[position] == 9 {
                        digits[position] = 0
                        position -= 1
                    }
                    if position >= 0 {
                        digits[position] += 1
                    } else {
                        digits.insert(1, at: 0)
                    }
                }
                integer = Array(digits.dropLast(precision))
                fraction = Array(digits.suffix(precision))
            } else {
                fraction += [UInt8](repeating: 0, count: precision - fraction.count)
            }
        }

        let leading = integer.drop { $0 == 0 }
        var text = value.sign == .minus ? "-" : ""
        text += leading.isEmpty ? "0" : String(decoding: leading.map { $0 + 0x30 }, as: UTF8.self)
        if !fraction.isEmpty {
            text += "."
            text += String(decoding: fraction.map { $0 + 0x30 }, as: UTF8.self)
        }
        return text
    }
}
