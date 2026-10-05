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

        // Integer specifiers are chosen per type, never from the target's
        // memory layout, so a key is the same on every architecture: `Int` is
        // `%lld` on wasm32 exactly as it is on arm64.

        /// Appends an integer argument, `%lld`.
        public mutating func appendInterpolation(_ value: Int) { appendSigned(Int64(value), "%lld") }
        /// Appends an integer argument, `%lld`.
        public mutating func appendInterpolation(_ value: Int64) { appendSigned(value, "%lld") }
        /// Appends an integer argument, `%d`.
        public mutating func appendInterpolation(_ value: Int32) { appendSigned(Int64(value), "%d") }
        /// Appends an integer argument, `%d`.
        public mutating func appendInterpolation(_ value: Int16) { appendSigned(Int64(value), "%d") }
        /// Appends an integer argument, `%d`.
        public mutating func appendInterpolation(_ value: Int8) { appendSigned(Int64(value), "%d") }
        /// Appends an unsigned integer argument, `%llu`.
        public mutating func appendInterpolation(_ value: UInt) { appendUnsigned(UInt64(value), "%llu") }
        /// Appends an unsigned integer argument, `%llu`.
        public mutating func appendInterpolation(_ value: UInt64) { appendUnsigned(value, "%llu") }
        /// Appends an unsigned integer argument, `%u`.
        public mutating func appendInterpolation(_ value: UInt32) { appendUnsigned(UInt64(value), "%u") }
        /// Appends an unsigned integer argument, `%u`.
        public mutating func appendInterpolation(_ value: UInt16) { appendUnsigned(UInt64(value), "%u") }
        /// Appends an unsigned integer argument, `%u`.
        public mutating func appendInterpolation(_ value: UInt8) { appendUnsigned(UInt64(value), "%u") }

        /// Appends an integer of any other type: `%lld` when the type is
        /// signed and `%llu` when it is unsigned, on every target.
        ///
        /// The argument is stored as `Int64` or `UInt64`. A value outside
        /// that range, such as a large `Int128`, is clamped to the nearest
        /// representable value.
        public mutating func appendInterpolation<T: BinaryInteger>(_ value: T) {
            if T.isSigned {
                appendSigned(Int64(clamping: value), "%lld")
            } else {
                appendUnsigned(UInt64(clamping: value), "%llu")
            }
        }

        private mutating func appendSigned(_ value: Int64, _ specifier: String) {
            key += specifier
            arguments.append(.integer(value))
        }

        private mutating func appendUnsigned(_ value: UInt64, _ specifier: String) {
            key += specifier
            arguments.append(.unsignedInteger(value))
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
        /// as `%2$lld`. Values outside `Int64` or `UInt64` are clamped.
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
