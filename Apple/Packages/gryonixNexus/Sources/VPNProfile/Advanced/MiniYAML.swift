import Foundation

public indirect enum YAMLValue: Equatable, Sendable {
    case scalar(String)
    case list([YAMLValue])
    case map([String: YAMLValue])
    case null

    public var string: String? {
        if case .scalar(let text) = self { return text }
        return nil
    }

    public var list: [YAMLValue]? {
        if case .list(let items) = self { return items }
        return nil
    }

    public var map: [String: YAMLValue]? {
        if case .map(let entries) = self { return entries }
        return nil
    }

    public subscript(key: String) -> YAMLValue? { map?[key] }
}

public enum MiniYAML {
    struct Line {
        var indent: Int
        var text: String
    }

    public static func parse(_ text: String) -> YAMLValue {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap { raw -> Line? in
            let stripped = stripComment(String(raw)).replacingOccurrences(of: "\t", with: "  ")
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "---" else { return nil }
            return Line(indent: stripped.prefix { $0 == " " }.count, text: trimmed)
        }
        var position = 0
        guard !lines.isEmpty else { return .null }
        return block(&lines, &position, indent: lines[0].indent)
    }

    /// Cuts a trailing comment that sits outside quotes
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for (offset, character) in line.enumerated() {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous == " " || offset == 0 {
                return String(line.prefix(offset))
            }
            previous = character
        }
        return line
    }

    static func block(_ lines: inout [Line], _ position: inout Int, indent: Int) -> YAMLValue {
        guard position < lines.count else { return .null }
        let first = lines[position].text
        if first == "-" || first.hasPrefix("- ") {
            return list(&lines, &position, indent: indent)
        }
        return map(&lines, &position, indent: indent)
    }

    static func list(_ lines: inout [Line], _ position: inout Int, indent: Int) -> YAMLValue {
        var items: [YAMLValue] = []
        while position < lines.count, lines[position].indent == indent,
              lines[position].text == "-" || lines[position].text.hasPrefix("- ") {
            let rest = String(lines[position].text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                position += 1
                items.append(nested(&lines, &position, above: indent))
            } else if splitKey(rest) != nil, !rest.hasPrefix("{"), !rest.hasPrefix("[") {
                let offset = lines[position].text.count - rest.count
                lines[position] = Line(indent: indent + offset, text: rest)
                items.append(map(&lines, &position, indent: indent + offset))
            } else {
                position += 1
                items.append(inline(rest))
            }
        }
        return .list(items)
    }

    static func map(_ lines: inout [Line], _ position: inout Int, indent: Int) -> YAMLValue {
        var entries: [String: YAMLValue] = [:]
        while position < lines.count, lines[position].indent == indent,
              let (key, value) = splitKey(lines[position].text) {
            position += 1
            if value.isEmpty {
                entries[key] = nestedOrSiblingList(&lines, &position, indent: indent)
            } else {
                entries[key] = inline(value)
            }
        }
        return .map(entries)
    }

    static func nested(_ lines: inout [Line], _ position: inout Int, above indent: Int) -> YAMLValue {
        guard position < lines.count, lines[position].indent > indent else { return .null }
        return block(&lines, &position, indent: lines[position].indent)
    }

    static func nestedOrSiblingList(_ lines: inout [Line], _ position: inout Int, indent: Int) -> YAMLValue {
        guard position < lines.count else { return .null }
        let next = lines[position]
        if next.indent == indent, next.text == "-" || next.text.hasPrefix("- ") {
            return list(&lines, &position, indent: indent)
        }
        return nested(&lines, &position, above: indent)
    }

    /// `key: value` split at the first colon outside quotes
    static func splitKey(_ text: String) -> (String, String)? {
        var quote: Character?
        let characters = Array(text)
        for (offset, character) in characters.enumerated() {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" || character == "[" {
                return nil
            } else if character == ":", offset + 1 == characters.count || characters[offset + 1] == " " {
                let key = String(characters[..<offset]).trimmingCharacters(in: .whitespaces)
                let value = String(characters[(offset + 1)...]).trimmingCharacters(in: .whitespaces)
                return (unquote(key), value)
            }
        }
        return nil
    }

    static func inline(_ text: String) -> YAMLValue {
        if text.hasPrefix("{") || text.hasPrefix("[") {
            var scanner = Flow(Array(text))
            return scanner.value()
        }
        if text == "~" || text == "null" { return .null }
        return .scalar(unquote(text))
    }

    static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        let body = String(text.dropFirst().dropLast())
        return first == "\"" ? body.replacingOccurrences(of: "\\\"", with: "\"") : body
    }

    /// Reads `{a: b}` and `[a, b]`
    struct Flow {
        let text: [Character]
        var index = 0

        init(_ text: [Character]) { self.text = text }

        mutating func value() -> YAMLValue {
            skipSpace()
            guard index < text.count else { return .null }
            if text[index] == "{" { return mapping() }
            if text[index] == "[" { return sequence() }
            return scalar()
        }

        mutating func mapping() -> YAMLValue {
            index += 1
            var entries: [String: YAMLValue] = [:]
            while true {
                skipSpace()
                guard index < text.count, text[index] != "}" else { break }
                let key = token(stopping: [":", ",", "}"])
                if index < text.count, text[index] == ":" {
                    index += 1
                    entries[key] = value()
                }
                skipSpace()
                if index < text.count, text[index] == "," { index += 1 }
            }
            index += 1
            return .map(entries)
        }

        mutating func sequence() -> YAMLValue {
            index += 1
            var items: [YAMLValue] = []
            while true {
                skipSpace()
                guard index < text.count, text[index] != "]" else { break }
                items.append(value())
                skipSpace()
                if index < text.count, text[index] == "," { index += 1 }
            }
            index += 1
            return .list(items)
        }

        mutating func scalar() -> YAMLValue {
            let raw = token(stopping: [",", "}", "]"])
            return raw == "~" || raw == "null" ? .null : .scalar(raw)
        }

        mutating func token(stopping stops: Set<Character>) -> String {
            skipSpace()
            var result = ""
            if index < text.count, text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index += 1
                while index < text.count, text[index] != quote {
                    result.append(text[index])
                    index += 1
                }
                index += 1
                return result
            }
            while index < text.count, !stops.contains(text[index]) {
                result.append(text[index])
                index += 1
            }
            return result.trimmingCharacters(in: .whitespaces)
        }

        mutating func skipSpace() {
            while index < text.count, text[index] == " " { index += 1 }
        }
    }
}
