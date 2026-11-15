import ServerControl
import ServiceCatalog
import SwiftUI

/// Settings → Modules
struct ModulesSettingsView: View {
    @ObservedObject private var modules = ModuleSettings.shared
    @ObservedObject private var ai = AISettings.shared
    @State private var askingAgreement: (() -> Void)?
    @State private var servers: [Deployment] = []

    var body: some View {
        Form {
            Section {
                Toggle("Keep modules on the servers", isOn: Binding(get: { modules.keptOnServers },
                                                                    set: { modules.keptOnServers = $0 }))
            } header: {
                InfoSectionHeader("Where modules are kept") {
                    Text("On: each server keeps its own modules in its agent, and every phone or Mac that manages it sees the same. Server modules (Docker networks, port forwarding) show only on servers that have them on; app modules show when any server has them on. Off: modules are kept on this device only.")
                    Text("Turned-off modules disappear from the app. Nothing is removed from your servers.")
                }
            }
            if modules.keptOnServers {
                ForEach(servers) { server in
                    NavigationLink(server.name) { ServerModulesView(server: server, ask: ask) }
                }
                if servers.isEmpty { Text("No servers yet").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(AppModule.allCases) { module in
                        ModuleToggle(module: module, isOn: modules.localIsOn(module)) { on in
                            ask(module, on) { modules.set(module, on: on) }
                        }
                    }
                } header: { Text("On this device") }
            }
        }
        .screenTitle("Modules")
        .task { servers = (try? FileDeploymentStore().load()) ?? [] }
        .sheet(isPresented: Binding(get: { askingAgreement != nil }, set: { if !$0 { askingAgreement = nil } })) {
            AIModuleAgreementSheet(
                onAgree: { ai.agreed = true; askingAgreement?(); askingAgreement = nil },
                onCancel: { askingAgreement = nil })
        }
    }

    /// Turning AI on needs the warning agreed first
    private func ask(_ module: AppModule, _ on: Bool, apply: @escaping () -> Void) {
        if module == .ai, on, !ai.agreed {
            askingAgreement = apply
        } else {
            apply()
        }
    }
}

/// One module's switch with what it adds behind an "i"
struct ModuleToggle: View {
    let module: AppModule
    let isOn: Bool
    let change: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: change)) {
            HStack {
                Text(LocalizedStringKey(module.title))
                InfoNote(title: LocalizedStringKey(module.title)) { Text(Self.note(module)) }
            }
        }
    }

    static func note(_ module: AppModule) -> LocalizedStringKey {
        switch module {
        case .ai: return "A tab where an AI explains problems, logs and commands. It only advises and never runs anything."
        case .vpnAdvanced: return "Subscriptions, rules, server groups, DNS, ad blocking and traffic statistics for this device's VPN."
        case .portForwarding: return "Reach a port on the server through the SSH connection, as if it were on this device."
        case .scripts: return "Your own shell scripts, kept on this device, run on a server you pick."
        case .dockerAdvanced: return "Docker's networks and disk use, next to containers, images and volumes."
        }
    }
}
