import SwiftLocalization

/// A failure to read, convert, or edit a string catalog.
package struct XCStringsError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Where in the document the problem is, such as
    /// `strings."cart.items".localizations.nl`, or a `line:column` position
    /// for JSON syntax errors.
    package var location: String
    package var message: String

    package init(location: String, message: String) {
        self.location = location
        self.message = message
    }

    package var description: String {
        location.isEmpty ? message : "\(location): \(message)"
    }
}

/// An Xcode string catalog (`.xcstrings`).
///
/// The document keeps the whole JSON tree, so fields this package does not
/// interpret survive ``serialized()`` unchanged. Supported schema: format
/// version 1.x with `sourceLanguage`, `strings`, and per-localization
/// `stringUnit`, plural and device `variations`, and `substitutions`.
package struct XCStringsDocument: Equatable, Sendable {
    package private(set) var root: JSONObject
    private var endsWithNewline: Bool
    private var escapesSlashes: Bool

    package init(parsing source: String) throws(XCStringsError) {
        let value: JSONValue
        do {
            value = try JSONParser.parse(source)
        } catch {
            throw XCStringsError(location: "\(error.line):\(error.column)", message: error.message)
        }
        guard let root = value.object else {
            throw XCStringsError(location: "", message: "a string catalog must be a JSON object")
        }
        self.root = root
        self.endsWithNewline = source.utf8.last == UInt8(ascii: "\n")
        // Follow the document's own choice; Xcode's is to escape.
        var slashes = 0, escapedSlashes = 0, previous: UInt8 = 0
        for byte in source.utf8 {
            if byte == UInt8(ascii: "/") {
                slashes += 1
                if previous == UInt8(ascii: "\\") { escapedSlashes += 1 }
            }
            previous = byte
        }
        self.escapesSlashes = escapedSlashes > 0 || slashes == 0

        guard let version = root["version"]?.string else {
            throw XCStringsError(location: "version", message: "missing format version")
        }
        guard version.split(separator: ".").first == "1" else {
            throw XCStringsError(
                location: "version",
                message: "unsupported string catalog version \"\(version)\"; this reader supports 1.x"
            )
        }
        guard root["sourceLanguage"]?.string != nil else {
            throw XCStringsError(location: "sourceLanguage", message: "missing source language")
        }
        guard root["strings"]?.object != nil else {
            throw XCStringsError(location: "strings", message: "missing strings table")
        }
    }

    /// The document as JSON text in Xcode's layout.
    ///
    /// A document that Xcode wrote and that was not edited serializes to the
    /// bytes it was parsed from.
    package func serialized() -> String {
        var serializer = JSONSerializer()
        serializer.escapesSlashes = escapesSlashes
        return serializer.serialize(.object(root)) + (endsWithNewline ? "\n" : "")
    }

    // MARK: - Conversion

    /// Converts the catalog to the format-neutral model.
    ///
    /// Every string unit with a value is included whatever its translation
    /// state. Comments, extraction state, and unknown fields are ignored.
    /// Unknown variation kinds and plural categories are errors.
    package func catalog() throws(XCStringsError) -> LocalizationCatalog {
        let sourceLanguage = try Self.locale(root["sourceLanguage"]?.string ?? "", at: "sourceLanguage")
        var catalog = LocalizationCatalog(sourceLanguage: sourceLanguage)
        for member in root["strings"]?.object?.members ?? [] {
            let path = "strings.\"\(member.key)\""
            guard let entry = member.value.object else {
                throw XCStringsError(location: path, message: "expected an object")
            }
            var localizations: [LocaleIdentifier: LocalizationCatalog.Localization] = [:]
            if let value = entry["localizations"] {
                guard let object = value.object else {
                    throw XCStringsError(location: path + ".localizations", message: "expected an object")
                }
                for localization in object.members {
                    let localizationPath = path + ".localizations." + localization.key
                    let locale = try Self.locale(localization.key, at: localizationPath)
                    guard localizations[locale] == nil else {
                        throw XCStringsError(location: localizationPath, message: "duplicate locale \"\(locale)\"")
                    }
                    localizations[locale] = try Self.localization(localization.value, at: localizationPath)
                }
            }
            catalog.entries[member.key] = LocalizationCatalog.Entry(localizations: localizations)
        }
        return catalog
    }

    private static func locale(_ identifier: String, at path: String) throws(XCStringsError) -> LocaleIdentifier {
        guard let locale = LocaleIdentifier(validating: identifier) else {
            throw XCStringsError(location: path, message: "\"\(identifier)\" is not a valid language tag")
        }
        return locale
    }

    private static func localization(
        _ value: JSONValue, at path: String
    ) throws(XCStringsError) -> LocalizationCatalog.Localization {
        guard let object = value.object else {
            throw XCStringsError(location: path, message: "expected an object")
        }
        var result = LocalizationCatalog.Localization(variation: try variation(object, at: path))
        if let value = object["substitutions"] {
            guard let substitutions = value.object else {
                throw XCStringsError(location: path + ".substitutions", message: "expected an object")
            }
            for member in substitutions.members {
                let substitutionPath = path + ".substitutions." + member.key
                guard let substitution = member.value.object else {
                    throw XCStringsError(location: substitutionPath, message: "expected an object")
                }
                guard let specifier = substitution["formatSpecifier"]?.string else {
                    throw XCStringsError(location: substitutionPath, message: "missing formatSpecifier")
                }
                var argumentIndex: Int?
                if let argNum = substitution["argNum"] {
                    guard case .number(let text) = argNum, let number = Int(text), number > 0 else {
                        throw XCStringsError(location: substitutionPath + ".argNum", message: "expected a positive integer")
                    }
                    argumentIndex = number
                }
                guard substitution["variations"] != nil else {
                    throw XCStringsError(location: substitutionPath, message: "missing variations")
                }
                result.substitutions[member.key] = LocalizationCatalog.Substitution(
                    argumentIndex: argumentIndex,
                    formatSpecifier: specifier,
                    variation: try variation(substitution, at: substitutionPath)
                )
            }
        }
        return result
    }

    /// Reads the `stringUnit` or `variations` of a localization, a variation
    /// case, or a substitution.
    private static func variation(
        _ object: JSONObject, at path: String
    ) throws(XCStringsError) -> LocalizationCatalog.Variation {
        if let value = object["variations"] {
            guard let variations = value.object, variations.members.count == 1, let kind = variations.members.first,
                  let cases = kind.value.object
            else {
                throw XCStringsError(location: path + ".variations", message: "expected exactly one variation kind")
            }
            let kindPath = path + ".variations." + kind.key
            switch kind.key {
            case "plural":
                var result: [PluralCategory: LocalizationCatalog.Variation] = [:]
                for member in cases.members {
                    guard let category = PluralCategory(rawValue: member.key) else {
                        throw XCStringsError(location: kindPath, message: "unknown plural category \"\(member.key)\"")
                    }
                    result[category] = try nested(member.value, at: kindPath + "." + member.key)
                }
                guard result[.other] != nil else {
                    throw XCStringsError(location: kindPath, message: "plural variation has no \"other\" case")
                }
                return .plural(.cardinal, result)
            case "device":
                var result: [String: LocalizationCatalog.Variation] = [:]
                for member in cases.members {
                    result[member.key] = try nested(member.value, at: kindPath + "." + member.key)
                }
                guard result["other"] != nil else {
                    throw XCStringsError(location: kindPath, message: "device variation has no \"other\" case")
                }
                return .device(result)
            default:
                throw XCStringsError(location: kindPath, message: "unsupported variation kind \"\(kind.key)\"")
            }
        }
        guard let unit = object["stringUnit"]?.object, let value = unit["value"]?.string else {
            throw XCStringsError(location: path, message: "expected a stringUnit with a value, or variations")
        }
        return .string(value)
    }

    private static func nested(_ value: JSONValue, at path: String) throws(XCStringsError) -> LocalizationCatalog.Variation {
        guard let object = value.object else {
            throw XCStringsError(location: path, message: "expected an object")
        }
        return try variation(object, at: path)
    }

    // MARK: - Editing

    /// Sets the plain string of `key` in `locale`, creating the key and the
    /// localization as needed and leaving every other field untouched.
    ///
    /// A new key is inserted before the first existing key that sorts after
    /// it. Throws rather than replace a localization that has variations.
    package mutating func setStringUnit(
        key: String, locale: LocaleIdentifier, value: String, state: String = "translated"
    ) throws(XCStringsError) {
        let path = "strings.\"\(key)\".localizations.\(locale)"
        var strings = root["strings"]?.object ?? JSONObject()
        var entry = JSONObject()
        if let existing = strings[key] {
            guard let object = existing.object else {
                throw XCStringsError(location: "strings.\"\(key)\"", message: "expected an object")
            }
            entry = object
        }
        var localizations = entry["localizations"]?.object ?? JSONObject()
        let localeKey = localizations.members.first { LocaleIdentifier(validating: $0.key) == locale }?.key
            ?? locale.identifier
        var localization = localizations[localeKey]?.object ?? JSONObject()
        guard localization["variations"] == nil else {
            throw XCStringsError(location: path, message: "refusing to replace a localization that has variations")
        }
        var unit = localization["stringUnit"]?.object ?? JSONObject()
        unit["state"] = .string(state)
        unit["value"] = .string(value)
        localization["stringUnit"] = .object(unit)
        localizations[localeKey] = .object(localization)
        entry["localizations"] = .object(localizations)

        if strings[key] != nil {
            strings[key] = .object(entry)
        } else {
            let position = strings.members.firstIndex { key < $0.key } ?? strings.members.count
            strings.members.insert(.init(key: key, value: .object(entry)), at: position)
        }
        root["strings"] = .object(strings)
    }
}
