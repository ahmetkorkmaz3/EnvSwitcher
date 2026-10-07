import Foundation

public struct DotEnvPair: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum DotEnvWarning: Equatable, Sendable {
    case invalidLine(line: Int)
    case unterminatedQuote(line: Int)
    case duplicateKey(key: String, line: Int)
}

public struct ParsedDotEnv: Equatable, Sendable {
    public var pairs: [DotEnvPair]
    public var warnings: [DotEnvWarning]
}

public enum DotEnvParser {
    public static func parse(_ text: String) -> ParsedDotEnv {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: "\n")

        var pairs: [DotEnvPair] = []
        var indexByKey: [String: Int] = [:]
        var warnings: [DotEnvWarning] = []
        var i = 0

        while i < lines.count {
            let lineNumber = i + 1
            var line = Substring(lines[i]).drop(while: isBlank)
            i += 1

            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = line.dropFirst("export ".count).drop(while: isBlank)
            }
            guard let eq = line.firstIndex(of: "=") else {
                warnings.append(.invalidLine(line: lineNumber))
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else {
                warnings.append(.invalidLine(line: lineNumber))
                continue
            }

            let rawRest = line[line.index(after: eq)...]
            let rest = rawRest.drop(while: isBlank)
            let value: String
            if let quote = rest.first, quote == "\"" || quote == "'" {
                var body = String(rest.dropFirst())
                var closed = closeQuoted(body, quote: quote)
                while closed == nil, i < lines.count {
                    body += "\n" + lines[i]
                    i += 1
                    closed = closeQuoted(body, quote: quote)
                }
                guard let closedValue = closed else {
                    warnings.append(.unterminatedQuote(line: lineNumber))
                    continue
                }
                value = closedValue
            } else {
                value = stripInlineComment(String(rawRest))
            }

            if let existing = indexByKey[key] {
                pairs[existing].value = value
                warnings.append(.duplicateKey(key: key, line: lineNumber))
            } else {
                indexByKey[key] = pairs.count
                pairs.append(DotEnvPair(key: key, value: value))
            }
        }
        return ParsedDotEnv(pairs: pairs, warnings: warnings)
    }

    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || (first.isASCII && first.isLetter) else { return false }
        return key.allSatisfy { c in
            c == "_" || c == "." || c == "-" || (c.isASCII && (c.isLetter || c.isNumber))
        }
    }

    private static func isBlank(_ c: Character) -> Bool { c == " " || c == "\t" }

    /// Returns the text before the closing quote, or nil when the quote does not close.
    private static func closeQuoted(_ body: String, quote: Character) -> String? {
        var result = ""
        var iterator = body.makeIterator()
        while let c = iterator.next() {
            if c == quote { return result }
            guard quote == "\"", c == "\\" else {
                result.append(c)
                continue
            }
            guard let next = iterator.next() else { return nil }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            default:
                result.append(c)
                result.append(next)
            }
        }
        return nil
    }

    /// A `#` starts a comment only when a space or tab comes before it.
    private static func stripInlineComment(_ raw: String) -> String {
        var result = ""
        var previous: Character = "="
        for c in raw {
            if c == "#", isBlank(previous) { break }
            result.append(c)
            previous = c
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
