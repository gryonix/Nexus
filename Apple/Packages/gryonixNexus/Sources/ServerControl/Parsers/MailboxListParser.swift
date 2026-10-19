import Foundation

public enum MailboxListParser {
    public static func parse(_ output: String) -> [Mailbox] {
        var mailboxes: [Mailbox] = []
        var seen: Set<String> = []
        for rawLine in ANSIStripper.strip(output).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                .trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                guard isAddress(line), seen.insert(line).inserted else { continue }
                mailboxes.append(Mailbox(address: line, detail: nil))
                continue
            }
            let address = String(line[line.startIndex..<separator])
            guard isAddress(address), seen.insert(address).inserted else { continue }
            let detail = line[separator...].trimmingCharacters(in: .whitespaces)
            mailboxes.append(Mailbox(address: address, detail: detail.isEmpty ? nil : detail))
        }
        return mailboxes
    }

    private static func isAddress(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        guard !token.contains(where: { "()<>[]{},;:\"'\\|".contains($0) }) else { return false }
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".") && !token.contains(where: \.isWhitespace)
    }
}
