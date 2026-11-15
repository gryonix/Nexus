/// One prompt for a small on-device model
public enum AIOnDevicePrompt {
    /// Characters kept within the small context window
    public static let budget = 6000

    /// The conversation as one prompt, newest kept, oldest cut
    public static func build(_ messages: [AIMessage], budget: Int = budget) -> String {
        guard let last = messages.last else { return "" }
        var lines: [String] = []
        var used = min(last.content.count, budget)
        for message in messages.dropLast().reversed() {
            let speaker = message.role == .assistant ? "Assistant" : "User"
            let line = "\(speaker): \(message.content)"
            if used + line.count > budget { break }
            used += line.count
            lines.insert(line, at: 0)
        }
        let request = String(last.content.suffix(budget))
        guard !lines.isEmpty else { return request }
        return "Conversation so far:\n" + lines.joined(separator: "\n\n") + "\n\nNow:\n" + request
    }
}
