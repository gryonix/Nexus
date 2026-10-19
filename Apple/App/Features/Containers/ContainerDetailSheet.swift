import AgentControl
import SwiftUI

@available(macOS 15.0, *)
struct ContainerDetailSheet: View {
    let container: ContainerSummary
    let load: @Sendable (String) async throws -> ContainerDetail

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ContainerDetail?
    @State private var failure: String?
    @State private var revealed: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section {
                        Text(verbatim: failure).foregroundStyle(.secondary)
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .rowActionButtonStyle()
                    }
                } else if let detail {
                    loaded(detail)
                } else {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: container.name))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private func loaded(_ detail: ContainerDetail) -> some View {
        Section {
            LabeledContent("Image") { mono(detail.container.image) }
            LabeledContent("State") { Text(verbatim: detail.container.state) }
            if !detail.container.health.isEmpty {
                LabeledContent("Health") { Text(verbatim: detail.container.health) }
            }
            if !detail.createdAt.isEmpty {
                LabeledContent("Created") { Text(verbatim: detail.createdAt) }
            }
            if !detail.restartPolicy.isEmpty {
                LabeledContent("Restart policy") { Text(verbatim: detail.restartPolicy) }
            }
        }

        if !detail.composeProject.isEmpty {
            Section("Compose") {
                LabeledContent("Project") { Text(verbatim: detail.composeProject) }
                if !detail.composeService.isEmpty {
                    LabeledContent("Service") { Text(verbatim: detail.composeService) }
                }
            }
        }

        if !detail.command.isEmpty {
            Section("Command") {
                mono(detail.command)
            }
        }

        if !detail.mounts.isEmpty {
            Section {
                ForEach(detail.mounts) { mount in
                    VStack(alignment: .leading, spacing: 2) {
                        mono(mount.destination)
                        HStack(spacing: 6) {
                            Text(verbatim: mount.kind.isEmpty ? "mount" : mount.kind)
                            Text(verbatim: "←")
                            Text(verbatim: mount.source)
                                .lineLimit(1)
                                .revealsFullText(mount.source)
                                .truncationMode(.middle)
                            if mount.isReadOnly { Text("read-only") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                InfoSectionHeader("Storage", note: "Where this container's data lives on the server.")
            }
        }

        if !detail.environment.isEmpty {
            Section {
                ForEach(detail.environment) { variable in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: variable.key)
                            .font(.caption.monospaced())
                        if variable.isSensitive && !revealed.contains(variable.key) {
                            Button("Show value") { revealed.insert(variable.key) }
                                .rowActionButtonStyle()
                                .font(.caption)
                        } else {
                            Text(verbatim: variable.value)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            } header: {
                InfoSectionHeader("Environment", note: "Values the server marked as credentials stay hidden until you ask for them.")
            }
        }
    }

    private func mono(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func load() async {
        failure = nil
        do {
            detail = try await load(container.name)
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }
}
