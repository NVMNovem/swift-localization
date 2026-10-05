/// A typed value captured from a string interpolation.
public enum LocalizationArgument: Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case floatingPoint(Double)
}

/// A string literal or interpolation that keeps its format key and typed
/// arguments until a locale is selected.
///
/// The key follows the conventions of `String.LocalizationValue`:
/// `"\(count) items"` has the key `%lld items` and one integer argument. In an
/// interpolated literal, a literal `%` is written to the key as `%%`. A literal
/// without interpolations is kept verbatim.
public struct LocalizationValue: Hashable, Sendable {
    /// The format string that identifies this value in a catalog.
    public var key: String
    /// The interpolated arguments, in source order.
    public var arguments: [LocalizationArgument]

    public init(key: String, arguments: [LocalizationArgument] = []) {
        self.key = key
        self.arguments = arguments
    }
}

extension LocalizationValue: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(key: value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var key = ""
        var arguments: [LocalizationArgument] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 4)
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            for character in literal {
                if character == "%" { key += "%" }
                key.append(character)
            }
        }

        /// Appends a string argument, `%@`.
        public mutating func appendInterpolation(_ value: String) {
            key += "%@"
            arguments.append(.string(value))
        }

        /// Appends an integer argument: `%lld` or `%llu`, and `%d` or `%u` for
        /// types of at most 32 bits.
        public mutating func appendInterpolation<T: BinaryInteger>(_ value: T) {
            let isWide = MemoryLayout<T>.size > 4
            if T.isSigned {
                key += isWide ? "%lld" : "%d"
                arguments.append(.integer(Int64(clamping: value)))
            } else {
                key += isWide ? "%llu" : "%u"
                arguments.append(.unsignedInteger(UInt64(clamping: value)))
            }
        }

        /// Appends a floating-point argument, `%lf`.
        public mutating func appendInterpolation(_ value: Double) {
            key += "%lf"
            arguments.append(.floatingPoint(value))
        }

        /// Appends a floating-point argument, `%f`.
        public mutating func appendInterpolation(_ value: Float) {
            key += "%f"
            arguments.append(.floatingPoint(Double(value)))
        }

        /// Appends a floating-point argument with an explicit format
        /// specifier such as `%.2f`.
        public mutating func appendInterpolation(_ value: Double, specifier: String) {
            key += specifier
            arguments.append(.floatingPoint(value))
        }

        /// Appends an integer argument with an explicit format specifier such
        /// as `%2$lld`.
        public mutating func appendInterpolation<T: BinaryInteger>(_ value: T, specifier: String) {
            key += specifier
            if T.isSigned {
                arguments.append(.integer(Int64(clamping: value)))
            } else {
                arguments.append(.unsignedInteger(UInt64(clamping: value)))
            }
        }
    }
}

/// A reference to a localizable string: a catalog key and the value used when
/// the catalog has no entry for it.
///
/// The shape follows `LocalizedStringResource`. The key stays distinct from
/// the default value even when one is inferred from the other.
public struct LocalizedResource: Hashable, Sendable {
    /// The catalog key.
    public var key: String
    /// The source-language value and the interpolated arguments.
    public var defaultValue: LocalizationValue

    public init(_ key: String, defaultValue: LocalizationValue) {
        self.key = key
        self.defaultValue = defaultValue
    }

    /// Creates a resource whose key is the format key of its value.
    public init(_ keyAndValue: LocalizationValue) {
        self.init(keyAndValue.key, defaultValue: keyAndValue)
    }
}

extension LocalizedResource: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(LocalizationValue(stringLiteral: value))
    }

    public init(stringInterpolation: LocalizationValue.StringInterpolation) {
        self.init(LocalizationValue(stringInterpolation: stringInterpolation))
    }
}
