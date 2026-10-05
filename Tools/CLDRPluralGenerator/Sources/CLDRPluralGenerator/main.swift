import Foundation

// Generates the checked-in CLDR plural tables and their conformance fixtures
// from the vendored cldr-json files in `Data/`. Run through `regenerate.sh`,
// which verifies the data checksums first.

struct Failure: Error, CustomStringConvertible {
    var description: String
}

let categories = ["zero", "one", "two", "few", "many", "other"]

// MARK: - Rule conditions

/// Translates one CLDR relation, such as `n % 10 = 2..4`, to a Swift
/// expression over a `PluralOperands` value named `o`.
func swiftRelation(_ relation: String) throws -> String {
    var tokens = relation.split(separator: " ").map(String.init)
    guard tokens.count >= 3 else { throw Failure(description: "malformed relation: \(relation)") }
    let operand = tokens.removeFirst()
    var modulus: String?
    if tokens.first == "%" {
        tokens.removeFirst()
        modulus = tokens.removeFirst()
        guard UInt64(modulus!) != nil else { throw Failure(description: "malformed modulus: \(relation)") }
    }
    let comparison = tokens.removeFirst()
    guard comparison == "=" || comparison == "!=" else {
        throw Failure(description: "unsupported operator in: \(relation)")
    }

    // `n` is the absolute value. Rule values are integers, so a relation on
    // `n` holds only for a number without non-zero fraction digits, whose
    // value is then `i`.
    let field: String
    switch operand {
    case "n", "i": field = "o.i"
    case "v": field = "o.v"
    case "w": field = "o.w"
    case "f": field = "o.f"
    case "t": field = "o.t"
    case "c", "e": field = "o.c"
    default: throw Failure(description: "unknown operand in: \(relation)")
    }
    let expression = modulus.map { "\(field) % \($0)" } ?? field

    let ranges = try tokens.joined().split(separator: ",").map { range -> String in
        let bounds = range.components(separatedBy: "..")
        guard bounds.allSatisfy({ UInt64($0) != nil }) else {
            throw Failure(description: "malformed range in: \(relation)")
        }
        switch bounds.count {
        case 1: return "\(expression) == \(bounds[0])"
        case 2: return "(\(bounds[0])...\(bounds[1])).contains(\(expression))"
        default: throw Failure(description: "malformed range in: \(relation)")
        }
    }
    guard !ranges.isEmpty else { throw Failure(description: "empty range list in: \(relation)") }

    var result = ranges.count == 1 ? ranges[0] : "(" + ranges.joined(separator: " || ") + ")"
    if operand == "n" {
        result = "(o.t == 0 && \(result))"
    }
    if comparison == "!=" {
        result = result.hasPrefix("(") ? "!\(result)" : "!(\(result))"
    }
    return result
}

func swiftCondition(_ condition: String) throws -> String {
    let alternatives = try condition.components(separatedBy: " or ").map { alternative in
        try alternative.components(separatedBy: " and ")
            .map { try swiftRelation($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: " && ")
    }
    return alternatives.joined(separator: " || ")
}

// MARK: - Samples

/// Expands a CLDR sample list (`0, 2~4, 1.0~1.5, 1c6, …`) to explicit decimal
/// strings.
func expandSamples(_ list: String) throws -> [String] {
    var samples: [String] = []
    for item in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        if item.isEmpty || item == "…" || item == "..." { continue }
        let bounds = item.components(separatedBy: "~")
        guard bounds.count == 2 else {
            samples.append(item)
            continue
        }
        func scaled(_ text: String) throws -> (value: Int, fractionDigits: Int) {
            guard text.allSatisfy({ $0.isNumber || $0 == "." }) else {
                throw Failure(description: "unsupported sample range: \(item)")
            }
            let parts = text.components(separatedBy: ".")
            let fraction = parts.count > 1 ? parts[1] : ""
            guard let value = Int(parts[0] + fraction) else {
                throw Failure(description: "unsupported sample range: \(item)")
            }
            return (value, fraction.count)
        }
        let (low, high) = (try scaled(bounds[0]), try scaled(bounds[1]))
        guard low.fractionDigits == high.fractionDigits, low.value <= high.value else {
            throw Failure(description: "unsupported sample range: \(item)")
        }
        for value in low.value...high.value {
            var digits = String(value)
            if low.fractionDigits > 0 {
                while digits.count <= low.fractionDigits { digits = "0" + digits }
                digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -low.fractionDigits))
            }
            samples.append(digits)
        }
    }
    return samples
}

// MARK: - Loading

struct LocaleRules {
    /// Swift conditions for every category except `other`, in category order.
    var conditions: [(category: String, condition: String)] = []
    var samples: [(category: String, samples: [String])] = []

    var signature: String {
        conditions.map { "\($0.category):\($0.condition)" }.joined(separator: "\n")
    }
}

func load(_ file: URL, section: String) throws -> (version: String, rules: [String: LocaleRules]) {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
    guard let supplemental = (root as? [String: Any])?["supplemental"] as? [String: Any],
          let version = (supplemental["version"] as? [String: Any])?["_cldrVersion"] as? String,
          let locales = supplemental[section] as? [String: [String: String]]
    else { throw Failure(description: "\(file.lastPathComponent): unexpected structure") }

    var result: [String: LocaleRules] = [:]
    for (locale, rules) in locales {
        var entry = LocaleRules()
        for category in categories {
            guard let rule = rules["pluralRule-count-\(category)"] else { continue }
            let parts = rule.components(separatedBy: "@")
            let condition = parts[0].trimmingCharacters(in: .whitespaces)
            if category == "other" {
                guard condition.isEmpty else { throw Failure(description: "\(locale): `other` has a condition") }
            } else {
                entry.conditions.append((category, try swiftCondition(condition)))
            }
            var samples: [String] = []
            for part in parts.dropFirst() {
                guard let space = part.firstIndex(of: " ") else { continue }
                samples += try expandSamples(String(part[space...]))
            }
            entry.samples.append((category, samples))
        }
        let known = Set(categories.map { "pluralRule-count-\($0)" })
        guard rules.keys.allSatisfy(known.contains) else {
            throw Failure(description: "\(locale): unknown plural category")
        }
        result[locale.lowercased()] = entry
    }
    return (version, result)
}

// MARK: - Emission

func run() throws {
    let toolDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let repository = toolDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let data = toolDirectory.appendingPathComponent("Data")

    var tag = ""
    for line in try String(contentsOf: data.appendingPathComponent("SOURCE"), encoding: .utf8).split(separator: "\n")
    where line.hasPrefix("tag: ") {
        tag = String(line.dropFirst(5))
    }
    guard !tag.isEmpty else { throw Failure(description: "Data/SOURCE has no tag") }

    let cardinal = try load(data.appendingPathComponent("plurals.json"), section: "plurals-type-cardinal")
    let ordinal = try load(data.appendingPathComponent("ordinals.json"), section: "plurals-type-ordinal")
    guard cardinal.version == ordinal.version else { throw Failure(description: "CLDR versions differ") }

    // Deduplicate identical rule sets across both rule types.
    var ruleIndex: [String: Int] = [:]
    var ruleSets: [LocaleRules] = []
    func index(of rules: LocaleRules) -> Int {
        if let existing = ruleIndex[rules.signature] { return existing }
        ruleIndex[rules.signature] = ruleSets.count
        ruleSets.append(rules)
        return ruleSets.count - 1
    }
    func table(_ rules: [String: LocaleRules]) -> (locales: [String], indices: [Int]) {
        let locales = rules.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return (locales, locales.map { index(of: rules[$0]!) })
    }
    let cardinalTable = table(cardinal.rules)
    let ordinalTable = table(ordinal.rules)
    guard ruleSets.count <= Int(UInt8.max) else { throw Failure(description: "too many rule sets") }

    let header = """
        // Generated by Tools/CLDRPluralGenerator from Unicode CLDR \(cardinal.version)
        // (unicode-org/cldr-json \(tag)). Do not edit.
        //
        // Source of truth: Tools/CLDRPluralGenerator/Data/plurals.json and ordinals.json.
        // Regenerate with: Tools/CLDRPluralGenerator/regenerate.sh
        //
        // The rule data is Copyright © Unicode, Inc. and used under the Unicode
        // License V3; see Tools/CLDRPluralGenerator/Data/LICENSE.
        """

    func arrayLiteral(_ items: [String], perLine: Int) -> String {
        stride(from: 0, to: items.count, by: perLine).map { start in
            "        " + items[start..<min(start + perLine, items.count)].joined(separator: ", ") + ","
        }.joined(separator: "\n")
    }

    var source = header + "\n\nextension CLDRPluralRules {\n"
    source += "    /// The CLDR release the plural rules were generated from.\n"
    source += "    public static let cldrVersion = \"\(cardinal.version)\"\n\n"
    for (name, table) in [("cardinal", cardinalTable), ("ordinal", ordinalTable)] {
        source += "    /// Lowercased locale identifiers with \(name) rules, sorted by UTF-8.\n"
        source += "    static let \(name)Locales: [String] = [\n"
        source += arrayLiteral(table.locales.map { "\"\($0)\"" }, perLine: 12) + "\n    ]\n\n"
        source += "    /// The rule set of each entry of `\(name)Locales`.\n"
        source += "    static let \(name)Rules: [UInt8] = [\n"
        source += arrayLiteral(table.indices.map(String.init), perLine: 24) + "\n    ]\n\n"
    }
    source += "    static func evaluate(rule: UInt8, _ o: PluralOperands) -> PluralCategory {\n"
    source += "        switch rule {\n"
    for (number, rules) in ruleSets.enumerated() where !rules.conditions.isEmpty {
        source += "        case \(number):\n"
        for (category, condition) in rules.conditions {
            source += "            if \(condition) { return .\(category) }\n"
        }
        source += "            return .other\n"
    }
    source += "        default:\n            return .other\n        }\n    }\n}\n"

    // Conformance fixtures: every CLDR sample with the category it must select.
    var fixtures: [String: [String]] = [:]
    for (type, rules) in [("cardinal", cardinal.rules), ("ordinal", ordinal.rules)] {
        for (locale, entry) in rules {
            for (category, samples) in entry.samples where !samples.isEmpty {
                fixtures["\(type)\t\(category)\t\(samples.joined(separator: " "))", default: []].append(locale)
            }
        }
    }
    let lines = fixtures.map { key, locales -> String in
        let fields = key.components(separatedBy: "\t")
        let sortedLocales = locales.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return "\(fields[0])\t\(fields[1])\t\(sortedLocales.joined(separator: " "))\t\(fields[2])"
    }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }

    var tests = header + "\n\n"
    tests += "/// One line per sample set: rule type, expected category, locales, and\n"
    tests += "/// samples, separated by tabs. Locales and samples are space-separated.\n"
    tests += "let cldrPluralSamples = #\"\"\"\n"
    tests += lines.map { "    " + $0 }.joined(separator: "\n")
    tests += "\n    \"\"\"#\n"

    try source.write(
        to: repository.appendingPathComponent("Sources/SwiftLocalization/Plurals/CLDRPluralRules+Generated.swift"),
        atomically: true, encoding: .utf8
    )
    try tests.write(
        to: repository.appendingPathComponent("Tests/SwiftLocalizationTests/CLDRPluralSamples+Generated.swift"),
        atomically: true, encoding: .utf8
    )
    print("CLDR \(cardinal.version) (\(tag)): \(cardinalTable.locales.count) cardinal and "
        + "\(ordinalTable.locales.count) ordinal locales, \(ruleSets.count) distinct rule sets, "
        + "\(lines.count) sample sets")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
