import ServerControl
import SwiftUI

struct ServerReorderView: View {
    @ObservedObject var viewModel: ServerListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReorderableList {
                Section {
                    ForEach(viewModel.deployments) { deployment in
                        row(deployment)
                    }
                    .onMove { viewModel.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    InfoSectionHeader("Servers", note: "Drag to reorder. This is the order servers appear in on the Servers tab.")
                }
            }
            .navigationTitle("Reorder Servers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    private func row(_ deployment: Deployment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: deployment.iconSymbol ?? "server.rack")
                .foregroundStyle(deployment.displayTint ?? .accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: deployment.name)
                Text(verbatim: deployment.entry.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
