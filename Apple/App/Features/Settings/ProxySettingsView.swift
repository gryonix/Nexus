import ServerControl
import SwiftUI

struct ProxySettingsView: View {
    @State private var proxies: [ProxyProfile] = []
    @State private var editing: ProxyProfile?

    var body: some View {
        Form {
            Section {
                if proxies.isEmpty {
                    Text("No proxy is set up.").foregroundStyle(.secondary)
                }
                ForEach(proxies) { proxy in
                    Button {
                        editing = proxy
                    } label: {
                        LabeledContent {
                            Text(verbatim: proxy.kind == .socks5 ? "SOCKS5" : "HTTP")
                                .foregroundStyle(.secondary)
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
                .onDelete { offsets in
                    for index in offsets { ProxyStore.remove(proxies[index].id) }
                    proxies = ProxyStore.all()
                }
                Button {
                    editing = ProxyProfile()
                } label: {
                    Label("Add a proxy", systemImage: "plus")
                }
                .rowActionButtonStyle()
            } header: {
                InfoSectionHeader("Proxies", note: "A proxy carries the connection to a server for you — the answer when this network refuses direct connections outright. A server picks one in its own settings, under Advanced. It is not a bastion: a bastion is a machine that connects onward on your behalf, and where both are set the proxy is dialled first.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Proxies")
        .raisedNavigationTitle()
        .task {
            proxies = ProxyStore.all()
            #if DEBUG
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_ADD_PROXY"] != nil {
                try? await Task.sleep(for: .milliseconds(600))
                editing = ProxyProfile()
            }
            #endif
        }
        .sheet(item: $editing) { proxy in
            ProxyEditorView(proxy: proxy) { saved, password in
                var list = ProxyStore.all()
                if let index = list.firstIndex(where: { $0.id == saved.id }) {
                    list[index] = saved
                } else {
                    list.append(saved)
                }
                ProxyStore.save(list)
                if let password { ProxyPasswordStore.save(password, for: saved.id) }
                proxies = ProxyStore.all()
            }
        }
    }
}

/// One proxy's own fields
struct ProxyEditorView: View {
    let proxy: ProxyProfile
    let onSave: (ProxyProfile, String?) -> Void

    @State private var draft: ProxyProfile
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    init(proxy: ProxyProfile, onSave: @escaping (ProxyProfile, String?) -> Void) {
        self.proxy = proxy
        self.onSave = onSave
        _draft = State(initialValue: proxy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Name", prompt: "Office", text: $draft.name)
                    WrappingPicker("Kind", selection: $draft.kind) {
                        Text(verbatim: "SOCKS5").tag(ProxyProfile.Kind.socks5)
                        Text(verbatim: "HTTP CONNECT").tag(ProxyProfile.Kind.httpConnect)
                    }
                    field("Host", prompt: "proxy.example.com", text: $draft.host)
                    LabeledContent("Port") {
                        TextField("Port", value: $draft.port,
                                  format: .number.grouping(.never),
                                  prompt: Text(verbatim: "1080").foregroundStyle(.secondary))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                } header: {
                    InfoSectionHeader("Proxy", note: "SOCKS5 carries any connection and is what a phone or a router usually offers. HTTP CONNECT is what a company's web proxy offers; it carries the same bytes through a different greeting.")
                }

                Section {
                    field("User", prompt: "optional", text: $draft.username)
                    SecureTechnicalField(title: "Password", text: $password)
                } header: {
                    Text("Sign-in")
                } footer: {
                    Text("Left empty, the proxy is used without a sign-in. The password is kept in this device's keychain, never in the server list.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .formRowButtons()
            .frame(minWidth: 420, minHeight: 320)
            #endif
            .navigationTitle(proxy.host.isEmpty ? "Add a proxy" : "Proxy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft, password.isEmpty ? nil : password)
                        dismiss()
                    }
                    .disabled(!draft.isUsable)
                }
            }
            .task {
                password = ""
            }
        }
    }

    private func field(_ title: LocalizedStringKey, prompt: LocalizedStringKey,
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
