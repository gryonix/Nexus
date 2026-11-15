import Foundation

/// What happened to each island card, kept across launches
@MainActor
final class IslandJournal: ObservableObject {
    static let shared = IslandJournal()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        let at: Date
        let run: String
        let text: String
    }

    @Published private(set) var entries: [Entry]

    static let limit = 300
    private static let key = "islandJournal.entries"

    private init() {
        entries = Self.load()
    }

    func note(_ text: String, run: String = "") {
        entries.append(Entry(at: Date(), run: run, text: text))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// The whole journal as lines to copy
    var plainText: String {
        entries.map(Self.line).joined(separator: "\n")
    }

    static func line(_ entry: Entry) -> String {
        let run = entry.run.isEmpty ? "" : " [\(entry.run)]"
        return "\(stamp.string(from: entry.at))\(run) \(entry.text)"
    }

    /// A job id short enough to read
    static func short(_ job: String) -> String {
        String(job.prefix(8))
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        return formatter
    }()

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
