#if os(iOS)
import SwiftUI

/// What happened to each island card, newest first
struct IslandJournalView: View {
    @ObservedObject private var journal = IslandJournal.shared

    var body: some View {
        List {
            if journal.entries.isEmpty {
                Text("Nothing recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(journal.entries.reversed()) { entry in
                IslandJournalRow(entry: entry)
            }
        }
        .bottomBarClearance()
        .screenTitle("Island journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: journal.plainText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(journal.entries.isEmpty)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Clear", role: .destructive) { journal.clear() }
                .dangerTint()
                .disabled(journal.entries.isEmpty)
        }
    }
}

private struct IslandJournalRow: View {
    let entry: IslandJournal.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.at, format: .dateTime.day().month().hour().minute().second())
                if !entry.run.isEmpty {
                    Text(entry.run).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}
#endif
