import ServerControl
import SwiftUI

// MARK: - Bastion

struct BastionPicker: View {
    @Binding var selection: BastionHop?
    let fleet: [Deployment]
    /// The server being edited
    let excluding: UUID?

    @State private var manualHost = ""
    @State private var manualPort = 22
    @State private var manualUser = "root"
    @Environment(\.dismiss) private var dismiss

    private var candidates: [Deployment] {
        fleet.filter { $0.id != excluding }
    }

    var body: some View {
        Form {
            Section {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    LabeledContent("None") {
                        if selection == nil {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            } header: {
                InfoSectionHeader("Bastion server", note: "Every connection to this server is made through the machine chosen here — the way in when the server itself is not reachable from the internet, or when only one machine is allowed to reach it. Nothing is stored on the server; this is the route this device takes.")
            }

            candidatesSection

            Section {
                formRow("Address", prompt: "jump.example.com", text: $manualHost)
                LabeledContent("Port") {
                    TextField("Port", value: $manualPort, format: .number,
                              prompt: Text(verbatim: "22").foregroundStyle(.secondary))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                formRow("User", prompt: "root", text: $manualUser)
                Button {
                    selection = .manual(HostEndpoint(
                        host: manualHost.trimmingCharacters(in: .whitespaces),
                        port: manualPort,
                        user: manualUser.trimmingCharacters(in: .whitespaces)))
                    dismiss()
                } label: {
                    Label("Use this host", systemImage: "arrow.triangle.branch")
                }
                .rowActionButtonStyle()
                .disabled(!manualEndpointIsValid)
            } header: {
                InfoSectionHeader("Another host", note: "A jump box this app does not manage. It signs in with this device's own key, which has to be authorized on that host the same way it is on a server.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Bastion server")
        .raisedNavigationTitle()
        .task {
            if let endpoint = selection?.manual {
                manualHost = endpoint.host
                manualPort = endpoint.port
                manualUser = endpoint.user
            }
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        if !candidates.isEmpty {
            Section {
                ForEach(candidates) { deployment in
                    Button {
                        selection = .fleetServer(deployment.id)
                        dismiss()
                    } label: {
                        LabeledContent {
                            if selection?.fleetServerID == deployment.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: deployment.name)
                                Text(verbatim: deployment.entry.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                InfoSectionHeader("Your servers", note: "A server this app already manages needs no address, account or key typed here — it has all three, and they stay right when the server changes.")
            }
        }
    }

    private var manualEndpointIsValid: Bool {
        HostEndpoint(host: manualHost.trimmingCharacters(in: .whitespaces),
                     port: manualPort,
                     user: manualUser.trimmingCharacters(in: .whitespaces)).isValid
    }

    private func formRow(_ title: LocalizedStringKey, prompt: LocalizedStringKey,
                         text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(.secondary))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        } label: {
            Text(title)
        }
    }
}

// MARK: - Fallback address

struct FallbackAddressView: View {
    @Binding var fallback: FallbackAddress?
    let fleet: [Deployment]
    let excluding: UUID?
    let primary: HostEndpoint

    @State private var host = ""
    @State private var port = 22
    @State private var bastion: BastionHop?

    var body: some View {
        Form {
            Section {
                LabeledContent("Host") {
                    TextField("Host", text: $host,
                              prompt: Text(verbatim: primary.host).foregroundStyle(.secondary))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number,
                              prompt: Text(verbatim: "\(primary.port)").foregroundStyle(.secondary))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                NavigationLink {
                    BastionPicker(selection: $bastion, fleet: fleet, excluding: excluding)
                } label: {
                    LabeledContent("Bastion server") {
                        Text(bastionSummary(bastion, fleet: fleet)).foregroundStyle(.secondary)
                    }
                }
            } header: {
                InfoSectionHeader("Fallback address", note: "Tried automatically when the server's usual address does not answer. Leave Host empty to retry the same address through the bastion chosen here. This is about reaching the machine — the copies of its data are a different screen, under Backups.")
            } footer: {
                if let fallback, !fallback.isUsable {
                    Text("A fallback with no address and no bastion would retry exactly what just failed.")
                        .foregroundStyle(.secondary)
                }
            }

            if fallback != nil {
                Section {
                    Button(role: .destructive) {
                        fallback = nil
                        host = ""
                        bastion = nil
                    } label: {
                        Label("Remove the fallback", systemImage: "trash")
                    }
                    .rowActionButtonStyle()
                    .dangerTint()
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Fallback address")
        .raisedNavigationTitle()
        .task {
            host = fallback?.host ?? ""
            port = fallback?.port ?? primary.port
            bastion = fallback?.bastion
        }
        .onChange(of: host) { _, _ in apply() }
        .onChange(of: port) { _, _ in apply() }
        .onChange(of: bastion) { _, _ in apply() }
    }

    private func apply() {
        let candidate = FallbackAddress(host: host.trimmingCharacters(in: .whitespaces),
                                        port: port == primary.port ? nil : port,
                                        bastion: bastion)
        fallback = candidate.isUsable ? candidate : nil
    }
}

// MARK: - Summaries

/// What a bastion row says when it is closed
func bastionSummary(_ hop: BastionHop?, fleet: [Deployment]) -> String {
    guard let hop, hop.isUsable else { return UIL10n.string("None") }
    if let id = hop.fleetServerID {
        return fleet.first { $0.id == id }?.name ?? UIL10n.string("Server not in the fleet")
    }
    return hop.manual?.host ?? UIL10n.string("None")
}

func fallbackSummary(_ fallback: FallbackAddress?) -> String {
    guard let fallback, fallback.isUsable else { return UIL10n.string("None") }
    let host = fallback.host.trimmingCharacters(in: .whitespaces)
    if host.isEmpty { return UIL10n.string("Through the bastion") }
    return host
}

// MARK: - Proxy

struct ProxyPickerView: View {
    @Binding var selection: UUID?

    @State private var proxies: [ProxyProfile] = []
    @State private var dismiss = DismissHandle()

    var body: some View {
        screen.dismissHandle(dismiss)
    }

    @ViewBuilder private var screen: some View {
        Form {
            Section {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    LabeledContent("None") {
                        if selection == nil {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                ForEach(proxies) { proxy in
                    Button {
                        selection = proxy.id
                        dismiss()
                    } label: {
                        LabeledContent {
                            if selection == proxy.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: proxy.displayName)
                                Text(verbatim: "\(proxy.host):\(proxy.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                InfoSectionHeader("Proxy", note: "The connection to this server is carried by the proxy chosen here — the answer when this network refuses direct connections. Where a bastion is also set, the proxy is dialled first and the bastion is reached through it.")
            }

            Section {
                NavigationLink {
                    ProxySettingsView()
                } label: {
                    Label("Manage proxies", systemImage: "arrow.triangle.swap")
                }
            } footer: {
                Text("Proxies are shared by every server that uses them, so they are kept in the app's own settings.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Proxy")
        .raisedNavigationTitle()
        .task { proxies = ProxyStore.all() }
    }
}

func proxySummary(_ id: UUID?) -> String {
    guard let id else { return UIL10n.string("None") }
    return ProxyStore.profile(id)?.displayName ?? UIL10n.string("Not in the list")
}
