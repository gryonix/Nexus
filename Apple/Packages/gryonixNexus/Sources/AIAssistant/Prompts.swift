import Foundation

public enum AIContextKind: String, Sendable {
    case problem, service, operation, weekly, terminalExplain, terminalAsk
}

/// Read-only facts handed to the model, redacted on assembly.
public struct AIContext: Equatable, Sendable {
    public var kind: AIContextKind
    public var title: String
    public var sections: [(label: String, text: String)]

    public init(kind: AIContextKind, title: String, sections: [(label: String, text: String)]) {
        self.kind = kind
        self.title = title
        self.sections = sections
    }

    public static func == (lhs: AIContext, rhs: AIContext) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title
            && lhs.sections.map(\.label) == rhs.sections.map(\.label)
            && lhs.sections.map(\.text) == rhs.sections.map(\.text)
    }
}

public enum AIPrompts {
    public static let maxSectionCharacters = 6000

    public static func systemPrompt(languageName: String) -> String {
        """
        You are an advisor inside a server-management app. You only explain and suggest.
        You cannot run commands, change servers or reach anything yourself, and you must \
        never claim or imply that you did or can.
        Offer commands only as suggestions the user should check first, each in a fenced \
        code block, with a short note on what it does and what to verify beforehand.
        If the data is not enough, say what is missing. Secrets are replaced by [REDACTED].
        Answer in \(languageName). Be concise.
        """
    }

    public static func contextMessage(_ context: AIContext) -> String {
        var parts = [intro(context.kind) + " " + Redactor.redact(context.title)]
        for section in context.sections where !section.text.isEmpty {
            let body = Redactor.redact(tail(section.text))
            parts.append("### \(section.label)\n```\n\(body)\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    public static func tail(_ text: String) -> String {
        text.count <= maxSectionCharacters ? text : "…" + String(text.suffix(maxSectionCharacters))
    }

    private static func intro(_ kind: AIContextKind) -> String {
        switch kind {
        case .problem: return "Explain this server problem and suggest what to check:"
        case .service: return "Explain what these service logs show and what may be wrong:"
        case .operation: return "This operation failed. Explain why and what to check:"
        case .weekly: return "Summarise the last 7 days for these servers, noting anything unusual:"
        case .terminalExplain: return "Explain this terminal command or output:"
        case .terminalAsk: return "Suggest commands for this need, as copy-only suggestions:"
        }
    }
}
