import Foundation

public enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case usage(input: Int, output: Int)
    case done
    case failure(String)
}

/// Turns server-sent-event lines into events.
public struct AIStreamParser {
    private let format: AIWireFormat
    private var input = 0

    public init(format: AIWireFormat) { self.format = format }

    public mutating func feed(line: String) -> [AIStreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let error = json["error"] as? [String: Any] {
            return [.failure(error["message"] as? String ?? "error")]
        }
        return format == .openAI ? openAI(json) : anthropic(json)
    }

    private func openAI(_ json: [String: Any]) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        let choice = (json["choices"] as? [[String: Any]])?.first
        if let text = (choice?["delta"] as? [String: Any])?["content"] as? String, !text.isEmpty {
            events.append(.text(text))
        }
        if let usage = json["usage"] as? [String: Any], let output = usage["completion_tokens"] as? Int {
            events.append(.usage(input: usage["prompt_tokens"] as? Int ?? 0, output: output))
        }
        return events
    }

    private mutating func anthropic(_ json: [String: Any]) -> [AIStreamEvent] {
        switch json["type"] as? String {
        case "content_block_delta":
            let text = (json["delta"] as? [String: Any])?["text"] as? String ?? ""
            return text.isEmpty ? [] : [.text(text)]
        case "message_start":
            let usage = (json["message"] as? [String: Any])?["usage"] as? [String: Any]
            input = usage?["input_tokens"] as? Int ?? 0
            return []
        case "message_delta":
            let output = (json["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
            return [.usage(input: input, output: output)]
        case "message_stop":
            return [.done]
        case "error":
            return [.failure((json["error"] as? [String: Any])?["message"] as? String ?? "error")]
        default:
            return []
        }
    }
}
