import AgentControl
import SwiftUI

/// Old restore copies, each with a delete button
struct PreRestoreCopiesList: View {
    let copies: [PreRestoreCopy]
    let delete: (PreRestoreCopy) async -> Void

    var body: some View {
        if !copies.isEmpty {
            Text("Old copies from restores")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(copies) { copy in
                row(copy)
            }
        }
    }

    private func row(_ copy: PreRestoreCopy) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: "\(sizeText(copy)) · \(dateText(copy))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            ConfirmedRemoveButton(
                title: "Delete this old copy?",
                message: Text("\(copy.name) is the data this service had before a restore. Deleting it frees the space and cannot be undone."),
                verb: "Delete"
            ) {
                Task { await delete(copy) }
            }
            .dangerTint()
            .glassIconButtonStyle()
            .labelStyle(.iconOnly)
        }
    }

    private func sizeText(_ copy: PreRestoreCopy) -> String {
        guard copy.sizeKnown else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(copy.sizeBytes), countStyle: .file)
    }

    private func dateText(_ copy: PreRestoreCopy) -> String {
        copy.movedAside.formatted(date: .abbreviated, time: .shortened)
    }
}
