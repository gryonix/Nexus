import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(Int, String)
    case code(language: String, text: String)
    case bullets([String])
    case numbered([String])
    case quote(String)
}

/// Block parser; an open fence runs on.
public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = text.components(separatedBy: "\n")[...]
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                blocks.append(fence(language: String(trimmed.dropFirst(3)), lines: &lines))
            } else if let item = listItem(trimmed) {
                flush()
                append(item, to: &blocks)
            } else if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
            } else if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.isEmpty {
                flush()
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    private static func fence(language: String, lines: inout ArraySlice<String>) -> MarkdownBlock {
        var body: [String] = []
        while let next = lines.popFirst() {
            if next.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
            body.append(next)
        }
        return .code(language: language.trimmingCharacters(in: .whitespaces),
                     text: body.joined(separator: "\n"))
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).hasPrefix(" ") else { return nil }
        return .heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return (false, String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (true, String(line.dropFirst(digits.count + 2)))
    }

    private static func append(_ item: (ordered: Bool, text: String), to blocks: inout [MarkdownBlock]) {
        switch (blocks.last, item.ordered) {
        case (.bullets(let items)?, false):
            blocks[blocks.count - 1] = .bullets(items + [item.text])
        case (.numbered(let items)?, true):
            blocks[blocks.count - 1] = .numbered(items + [item.text])
        default:
            blocks.append(item.ordered ? .numbered([item.text]) : .bullets([item.text]))
        }
    }
}
