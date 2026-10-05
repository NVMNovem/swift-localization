/// A parsed `printf`-style localization format string.
///
/// The supported surface is deliberately small: `%%`, `%@`, the integer
/// conversions `d i u` with any length modifier, the fixed-point conversion
/// `f` with an optional precision, positional arguments (`%1$@`), and named
/// substitutions (`%#@name@`). Flags, field widths, and every other
/// conversion are rejected rather than approximated.
enum FormatString {
    enum Conversion: Equatable {
        case object
        case signed
        case unsigned
        case float(precision: Int?)
        /// `%arg`: the argument of the enclosing substitution.
        case substitutionArgument
    }

    enum Segment: Equatable {
        case literal(String)
        /// `position` is 1-based.
        case argument(position: Int?, conversion: Conversion, specifier: String)
        case substitution(name: String, position: Int?)
    }

    struct UnsupportedSpecifier: Error {
        var specifier: String
    }

    static func parse(_ format: String, allowsSubstitutionArgument: Bool = false) throws(UnsupportedSpecifier) -> [Segment] {
        let scalars = Array(format.unicodeScalars)
        var segments: [Segment] = []
        var literal = String.UnicodeScalarView()
        var index = 0

        func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar >= "0" && scalar <= "9" }
        /// The specifier text from `start` through its conversion character.
        func text(from start: Int) -> String {
            var end = index
            while end < scalars.count, "0123456789.#+- '*$hlqLztj".unicodeScalars.contains(scalars[end]) {
                end += 1
            }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[start..<min(end + 1, scalars.count)])
            return String(view)
        }
        func digits() -> Int? {
            var value: Int?
            while index < scalars.count, isDigit(scalars[index]), (value ?? 0) < 100_000 {
                value = (value ?? 0) * 10 + Int(scalars[index].value - 0x30)
                index += 1
            }
            return value
        }

        while index < scalars.count {
            guard scalars[index] == "%" else {
                literal.append(scalars[index])
                index += 1
                continue
            }
            let start = index
            index += 1
            guard index < scalars.count else { throw UnsupportedSpecifier(specifier: "%") }
            if scalars[index] == "%" {
                literal.append("%")
                index += 1
                continue
            }
            if !literal.isEmpty {
                segments.append(.literal(String(literal)))
                literal = String.UnicodeScalarView()
            }

            var position: Int?
            if let number = digits() {
                // Digits not followed by `$` are a field width.
                guard index < scalars.count, scalars[index] == "$", number > 0 else {
                    throw UnsupportedSpecifier(specifier: text(from: start))
                }
                position = number
                index += 1
            }

            if index + 1 < scalars.count, scalars[index] == "#", scalars[index + 1] == "@" {
                index += 2
                var name = String.UnicodeScalarView()
                while index < scalars.count, scalars[index] != "@" {
                    name.append(scalars[index])
                    index += 1
                }
                guard index < scalars.count, !name.isEmpty else {
                    throw UnsupportedSpecifier(specifier: text(from: start))
                }
                index += 1
                segments.append(.substitution(name: String(name), position: position))
                continue
            }

            if allowsSubstitutionArgument, index + 2 < scalars.count,
               scalars[index] == "a", scalars[index + 1] == "r", scalars[index + 2] == "g" {
                index += 3
                segments.append(.argument(position: position, conversion: .substitutionArgument, specifier: "%arg"))
                continue
            }

            var precision: Int?
            if index < scalars.count, scalars[index] == "." {
                index += 1
                precision = digits() ?? 0
            }
            while index < scalars.count, "hlqLztj".unicodeScalars.contains(scalars[index]) {
                index += 1
            }
            guard index < scalars.count else { throw UnsupportedSpecifier(specifier: text(from: start)) }

            let conversion: Conversion
            switch scalars[index] {
            case "@" where precision == nil: conversion = .object
            case "d" where precision == nil, "i" where precision == nil, "D" where precision == nil:
                conversion = .signed
            case "u" where precision == nil, "U" where precision == nil: conversion = .unsigned
            case "f", "F": conversion = .float(precision: precision)
            default: throw UnsupportedSpecifier(specifier: text(from: start))
            }
            segments.append(.argument(position: position, conversion: conversion, specifier: text(from: start)))
            index += 1
        }
        if !literal.isEmpty { segments.append(.literal(String(literal))) }
        return segments
    }
}
