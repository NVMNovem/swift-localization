/// A JSON value that keeps what a read-modify-write cycle must not lose:
/// member order and the exact spelling of numbers.
package enum JSONValue: Equatable, Sendable {
    case object(JSONObject)
    case array([JSONValue])
    case string(String)
    /// The number as written in the source.
    case number(String)
    case bool(Bool)
    case null

    package var object: JSONObject? {
        if case .object(let object) = self { object } else { nil }
    }

    package var string: String? {
        if case .string(let string) = self { string } else { nil }
    }
}

/// A JSON object with ordered members and unique keys.
package struct JSONObject: Equatable, Sendable {
    package struct Member: Equatable, Sendable {
        package var key: String
        package var value: JSONValue
    }

    package var members: [Member] = []

    package init() {}

    /// Reads a member, replaces it in place, appends a new one, or removes it.
    package subscript(key: String) -> JSONValue? {
        get { members.first { $0.key == key }?.value }
        set {
            let index = members.firstIndex { $0.key == key }
            switch (index, newValue) {
            case (let index?, let value?): members[index].value = value
            case (let index?, nil): members.remove(at: index)
            case (nil, let value?): members.append(Member(key: key, value: value))
            case (nil, nil): break
            }
        }
    }
}

package struct JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
    package var message: String
    /// 1-based line and column of the offending byte.
    package var line: Int
    package var column: Int

    package var description: String { "\(line):\(column): \(message)" }
}

package struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    package static func parse(_ source: String) throws(JSONParseError) -> JSONValue {
        var parser = JSONParser(bytes: Array(source.utf8))
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3 }
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("unexpected content after the top-level value") }
        return value
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private func error(_ message: String) -> JSONParseError {
        var line = 1
        var column = 1
        for byte in bytes[..<min(index, bytes.count)] {
            if byte == UInt8(ascii: "\n") {
                line += 1
                column = 1
            } else if byte & 0xC0 != 0x80 {
                column += 1
            }
        }
        return JSONParseError(message: message, line: line, column: column)
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
            index += 1
        }
    }

    private mutating func value(depth: Int) throws(JSONParseError) -> JSONValue {
        guard depth < 256 else { throw error("JSON is nested too deeply") }
        skipWhitespace()
        guard let byte = current else { throw error("unexpected end of input") }
        switch byte {
        case UInt8(ascii: "{"):
            index += 1
            var object = JSONObject()
            var seen: Set<String> = []
            skipWhitespace()
            if current == UInt8(ascii: "}") {
                index += 1
                return .object(object)
            }
            while true {
                skipWhitespace()
                guard current == UInt8(ascii: "\"") else { throw error("expected a string key") }
                let keyStart = index
                let key = try string()
                guard seen.insert(key).inserted else {
                    index = keyStart
                    throw error("duplicate key \"\(key)\"")
                }
                skipWhitespace()
                guard current == UInt8(ascii: ":") else { throw error("expected ':'") }
                index += 1
                object.members.append(.init(key: key, value: try value(depth: depth + 1)))
                skipWhitespace()
                if current == UInt8(ascii: ",") {
                    index += 1
                } else if current == UInt8(ascii: "}") {
                    index += 1
                    return .object(object)
                } else {
                    throw error("expected ',' or '}'")
                }
            }
        case UInt8(ascii: "["):
            index += 1
            var array: [JSONValue] = []
            skipWhitespace()
            if current == UInt8(ascii: "]") {
                index += 1
                return .array(array)
            }
            while true {
                array.append(try value(depth: depth + 1))
                skipWhitespace()
                if current == UInt8(ascii: ",") {
                    index += 1
                } else if current == UInt8(ascii: "]") {
                    index += 1
                    return .array(array)
                } else {
                    throw error("expected ',' or ']'")
                }
            }
        case UInt8(ascii: "\""):
            return .string(try string())
        case UInt8(ascii: "t"):
            try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try literal("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try number())
        default:
            throw error("unexpected character")
        }
    }

    private mutating func literal(_ text: StaticString) throws(JSONParseError) {
        let expected = Array("\(text)".utf8)
        guard bytes[index...].starts(with: expected) else { throw error("unexpected character") }
        index += expected.count
    }

    private mutating func number() throws(JSONParseError) -> String {
        let start = index
        func isDigit(_ byte: UInt8?) -> Bool { byte.map { $0 >= 0x30 && $0 <= 0x39 } ?? false }
        if current == UInt8(ascii: "-") { index += 1 }
        guard isDigit(current) else { throw error("malformed number") }
        if current == UInt8(ascii: "0") {
            index += 1
        } else {
            while isDigit(current) { index += 1 }
        }
        if current == UInt8(ascii: ".") {
            index += 1
            guard isDigit(current) else { throw error("malformed number") }
            while isDigit(current) { index += 1 }
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            index += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { index += 1 }
            guard isDigit(current) else { throw error("malformed number") }
            while isDigit(current) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func hexUnit() throws(JSONParseError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("malformed \\u escape") }
        var unit: UInt32 = 0
        for byte in bytes[index..<index + 4] {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw error("malformed \\u escape")
            }
            unit = unit << 4 | UInt32(digit)
        }
        index += 4
        return unit
    }

    private mutating func string() throws(JSONParseError) -> String {
        index += 1
        var result: [UInt8] = []
        while true {
            guard let byte = current else { throw error("unterminated string") }
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                // The source is a `String` and escapes append whole scalars, so
                // the bytes are valid UTF-8.
                return String(decoding: result, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard let escape = current else { throw error("unterminated string") }
                index += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): result.append(escape)
                case UInt8(ascii: "b"): result.append(0x08)
                case UInt8(ascii: "f"): result.append(0x0C)
                case UInt8(ascii: "n"): result.append(0x0A)
                case UInt8(ascii: "r"): result.append(0x0D)
                case UInt8(ascii: "t"): result.append(0x09)
                case UInt8(ascii: "u"):
                    var scalarValue = try hexUnit()
                    if (0xD800...0xDBFF).contains(scalarValue) {
                        guard current == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") else {
                            throw error("unpaired surrogate in \\u escape")
                        }
                        index += 2
                        let low = try hexUnit()
                        guard (0xDC00...0xDFFF).contains(low) else { throw error("unpaired surrogate in \\u escape") }
                        scalarValue = 0x10000 + ((scalarValue - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(scalarValue) else {
                        throw error("unpaired surrogate in \\u escape")
                    }
                    result.append(contentsOf: String(scalar).utf8)
                default:
                    index -= 1
                    throw error("invalid escape sequence")
                }
            case 0..<0x20:
                index -= 1
                throw error("unescaped control character in string")
            default:
                result.append(byte)
            }
        }
    }
}

/// Serializes JSON in the layout Xcode uses for string catalogs: two-space
/// indentation, `"key" : value`, and a blank line inside empty containers.
package struct JSONSerializer {
    /// Whether `/` is written as `\/`.
    package var escapesSlashes = true

    package init() {}

    package func serialize(_ value: JSONValue) -> String {
        var output = ""
        write(value, indent: 0, to: &output)
        return output
    }

    private func write(_ value: JSONValue, indent: Int, to output: inout String) {
        let padding = String(repeating: "  ", count: indent)
        switch value {
        case .object(let object):
            output += "{\n"
            for (offset, member) in object.members.enumerated() {
                output += padding + "  "
                write(member.key, to: &output)
                output += " : "
                write(member.value, indent: indent + 1, to: &output)
                if offset < object.members.count - 1 { output += "," }
                output += "\n"
            }
            if object.members.isEmpty { output += "\n" }
            output += padding + "}"
        case .array(let array):
            output += "[\n"
            for (offset, element) in array.enumerated() {
                output += padding + "  "
                write(element, indent: indent + 1, to: &output)
                if offset < array.count - 1 { output += "," }
                output += "\n"
            }
            if array.isEmpty { output += "\n" }
            output += padding + "]"
        case .string(let string):
            write(string, to: &output)
        case .number(let number):
            output += number
        case .bool(let bool):
            output += bool ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private func write(_ string: String, to output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "/" where escapesSlashes: output += "\\/"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
