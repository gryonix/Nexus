import Foundation

public struct OpenVPNProfileConfig: Equatable, Sendable {
    public let rawText: String
    /// The directives as the payload's `VendorConfig` dictionary
    public let vendorConfig: [String: String]

    /// Reasons, not sentences — see `WireGuardQuickConfig.ParseError`
    public enum ParseError: Error, Equatable {
        case noDirectives
        case noRemote
        case unterminatedInlineBlock(String)
    }

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var directives = try Self.directives(in: trimmed)
        guard !directives.isEmpty else { throw ParseError.noDirectives }
        guard directives.contains(where: { $0.name == "remote" }) else { throw ParseError.noRemote }

        let hasCertificate = directives.contains { $0.name == "ca" || $0.name == "cert" }
        if !hasCertificate {
            directives.append((name: "setenv", value: "CLIENT_CERT 0"))
        }

        var config = Self.numbered(directives)
        config["vpn-on-demand"] = "0"

        self.rawText = trimmed
        self.vendorConfig = config
        self.remoteEndpoint = Self.remoteEndpoint(in: config)
    }

    public let remoteEndpoint: String?

    private static func remoteEndpoint(in config: [String: String]) -> String? {
        guard let value = config["remote.1"] ?? config["remote"] else { return nil }
        guard value != "NOARGS" else { return nil }
        let fields = value.split(separator: " ").map(String.init)
        guard let host = fields.first, !host.isEmpty else { return nil }
        guard fields.count > 1, let port = Int(fields[1]), (1...65_535).contains(port) else {
            return host
        }
        return "\(host):\(port)"
    }

    // MARK: - Reading the file

    private typealias Directive = (name: String, value: String)

    private static func directives(in text: String) throws -> [Directive] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var directives: [Directive] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if let name = inlineBlockName(line) {
                let body = try inlineBlockBody(named: name, from: lines, startingAt: &index)
                directives.append((name: name, value: escaped(body)))
                continue
            }

            guard let separator = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                directives.append((name: line, value: "NOARGS"))
                continue
            }
            let name = String(line[..<separator])
            let arguments = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            directives.append((name: name,
                               value: arguments.isEmpty ? "NOARGS" : escaped(arguments)))
        }
        return directives
    }

    /// `<ca>` → `ca`
    private static func inlineBlockName(_ line: String) -> String? {
        guard line.hasPrefix("<"), line.hasSuffix(">"), !line.hasPrefix("</") else { return nil }
        let name = String(line.dropFirst().dropLast())
        return name.isEmpty ? nil : name
    }

    /// Everything up to `</name>`, verbatim
    private static func inlineBlockBody(named name: String,
                                        from lines: [String],
                                        startingAt index: inout Int) throws -> String {
        var body: [String] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line == "</\(name)>" {
                while body.first?.isEmpty == true { body.removeFirst() }
                while body.last?.isEmpty == true { body.removeLast() }
                return body.joined(separator: "\n")
            }
            body.append(line)
        }
        throw ParseError.unterminatedInlineBlock(name)
    }

    private static func numbered(_ directives: [Directive]) -> [String: String] {
        var totals: [String: Int] = [:]
        for directive in directives { totals[directive.name, default: 0] += 1 }

        var seen: [String: Int] = [:]
        var config: [String: String] = [:]
        for directive in directives {
            guard totals[directive.name, default: 0] > 1 else {
                config[directive.name] = directive.value
                continue
            }
            seen[directive.name, default: 0] += 1
            config["\(directive.name).\(seen[directive.name]!)"] = directive.value
        }
        return config
    }

    /// The payload's escaping model: every value is one line
    static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
