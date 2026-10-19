import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

struct MeshDevicesView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var shownKey: ShownKey?
    @State private var isMinting = false
    @State private var publishedNames: [MeshName] = []

    private struct ShownKey: Identifiable {
        let id = UUID()
        let key: MeshAuthKey
    }

    var body: some View {
        CardList {
            Section {
                content
            } header: {
                InfoSectionHeader("Devices", note: "Every device that joined this mesh. They reach each other directly, and this server relays only when a network refuses a direct connection.")
            }

            devicesSection

            Section {
                Button {
                    Task { publishedNames = await viewModel.publishMeshNames() }
                } label: {
                    Label("Publish service names", systemImage: "arrow.up.doc")
                }
                .rowActionButtonStyle()
                ForEach(publishedNames) { record in
                    HStack {
                        Text(verbatim: record.name).font(.caption)
                        Spacer()
                        Text(verbatim: record.address)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                InfoSectionHeader("Names inside the mesh", note: "Makes this server's services reachable from your devices by their usual names, even where those names do not resolve publicly. The addresses stay private to the mesh.")
            }
        }
        .navigationTitle("Mesh devices")
        .raisedNavigationTitle()
        .refreshableWithShortcut { await viewModel.loadMeshNodes() }
        .task { await viewModel.loadMeshNodes() }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_MESH_KEY"] == "1" else { return }
            shownKey = ShownKey(key: MeshAuthKey(key: "hskey-auth-EXAMPLEONLYnotarealkey",
                                                 isReusable: false,
                                                 expiresAt: Date().addingTimeInterval(86_400)))
        }
        #endif
        .sheet(item: $shownKey) { shown in
            MeshJoinKeySheet(key: shown.key,
                             loginServer: viewModel.meshLoginServer) {
                shownKey = nil
                Task { await viewModel.loadMeshNodes() }
            }
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        Section {
            Button {
                guard LicensePrompt.shared.allow() else { return }
                Task {
                    isMinting = true
                    defer { isMinting = false }
                    if let key = await viewModel.mintMeshJoinKey() {
                        shownKey = ShownKey(key: key)
                    }
                }
            } label: {
                HStack {
                    Label("Add device", systemImage: "plus.circle")
                    if isMinting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .rowActionButtonStyle()
            .disabled(isMinting)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.meshNodes {
        case .loaded(let nodes):
            if nodes.isEmpty {
                Text("No devices yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nodes) { node in
                    row(node)
                }
            }
        case .loading, .idle:
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message):
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ node: MeshNode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                HStack(spacing: 6) {
                    Text(verbatim: node.addresses.first ?? "")
                        .font(.caption.monospaced())
                    if !node.user.isEmpty {
                        Text(verbatim: node.user)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(node.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityLabel(node.isOnline ? Text("Online") : Text("Offline"))
            ConfirmedRemoveButton(
                title: "Remove this device?",
                message: Text("\(node.name) leaves the mesh immediately. It can join again with a new key.")
            ) {
                let id = node.id
                Task { await viewModel.removeMeshNode(id: id) }
            }
            .dangerTint()
            .glassIconButtonStyle()
            .labelStyle(.iconOnly)
        }
    }
}

/// The join key, with the command that uses it
struct MeshJoinKeySheet: View {
    let key: MeshAuthKey
    let loginServer: String
    let onClose: () -> Void

    private var command: String {
        "tailscale up --login-server \(loginServer) --authkey \(key.key)"
    }

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    Text(verbatim: key.key)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Join key")
                } footer: {
                    if let expiresAt = key.expiresAt {
                        Text("Valid until \(expiresAt.formatted(date: .abbreviated, time: .shortened)). It is shown only now — the server does not hand it back.")
                    } else {
                        Text("It is shown only now — the server does not hand it back.")
                    }
                }

                Section {
                    Text(verbatim: command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        copyToClipboard(command)
                    } label: {
                        Label("Copy command", systemImage: "doc.on.doc")
                    }
                    .rowActionButtonStyle()
                } header: {
                    InfoSectionHeader("On the device", note: "Install the official Tailscale client, then run this. On a phone, use the app's “Use custom coordination server” option with the same address.")
                }
            }
            .navigationTitle("Add device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }

    private func copyToClipboard(_ string: String) {
        SecretPasteboard.copy(string)
    }
}

#if DEBUG
struct MeshDevicesTarget: Hashable {
    let deployment: Deployment
}
#endif
