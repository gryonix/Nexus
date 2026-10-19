import ServerControl
import SwiftUI

struct ServerMultiExportView: View {
    let deployments: [Deployment]
    let onExport: ([Deployment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(deployments) { deployment in
                        Button {
                            toggle(deployment)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: deployment.iconSymbol ?? "server.rack")
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: deployment.name)
                                        .foregroundStyle(.primary)
                                    if !deployment.domain.isEmpty {
                                        Text(verbatim: deployment.domain)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: selected.contains(deployment.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(deployment.id)
                                                     ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Each server is exported with its credentials, so treat the files like passwords.")
                }
            }
            .navigationTitle("Export servers")
            .raisedNavigationTitle()
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 320)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export") {
                        onExport(deployments.filter { selected.contains($0.id) })
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(selected.count == deployments.count ? "Deselect all" : "Select all") {
                        selected = selected.count == deployments.count
                            ? [] : Set(deployments.map(\.id))
                    }
                }
            }
        }
    }

    private func toggle(_ deployment: Deployment) {
        if selected.contains(deployment.id) {
            selected.remove(deployment.id)
        } else {
            selected.insert(deployment.id)
        }
    }
}
