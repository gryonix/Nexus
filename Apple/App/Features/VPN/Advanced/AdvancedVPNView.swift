import SwiftUI
import VPNProfile

struct AdvancedVPNView: View {
    @ObservedObject var model: AdvancedVPNModel
    @ObservedObject var tunnel: TunnelController

    var body: some View {
        Form {
            activeSection
            Section {
                NavigationLink("Import") { AdvancedImportView(model: model) }
                NavigationLink("Servers (\(model.profile.servers.count))") { AdvancedServersView(model: model) }
                NavigationLink("Groups (\(model.profile.groups.count))") { AdvancedGroupsView(model: model) }
                NavigationLink("Rules (\(model.profile.rules.count))") { AdvancedRulesView(model: model) }
                NavigationLink("DNS") { AdvancedDNSView(model: model) }
                NavigationLink("Block lists (\(model.profile.blockLists.count))") { AdvancedBlockListsView(model: model) }
                NavigationLink("Host rewrites (\(model.profile.hosts.count))") { AdvancedRewritesView(model: model) }
                NavigationLink("Traffic") { AdvancedTrafficView(model: model, tunnel: tunnel) }
            }
            if let message = model.message {
                Section { Text(verbatim: message).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .screenTitle("Advanced")
        .task { await model.refreshDue() }
    }

    private var activeSection: some View {
        Section {
            Picker("Runs", selection: activeBinding) {
                Text("Nothing chosen").tag("")
                ForEach(model.profile.groups) { Text(verbatim: $0.name).tag($0.id) }
                ForEach(model.profile.servers) { Text(verbatim: $0.name).tag($0.id) }
            }
            Picker("Everything else", selection: finalBinding) {
                ForEach(AdvancedRule.Action.allCases, id: \.self) { Text(AdvancedLabels.action($0)).tag($0) }
            }
            Button("Apply") { Task { await model.apply(to: tunnel, connect: false) } }
                .disabled(model.profile.servers.isEmpty)
        } header: {
            InfoSectionHeader("Advanced VPN") {
                Text("Several servers, your own rules and DNS. Apply puts them into the tunnel; a running tunnel restarts.")
            }
        }
    }

    private var activeBinding: Binding<String> {
        Binding(get: { model.profile.activeID ?? "" },
                set: { value in model.update { $0.activeID = value.isEmpty ? nil : value } })
    }

    private var finalBinding: Binding<AdvancedRule.Action> {
        Binding(get: { model.profile.finalAction }, set: { value in model.update { $0.finalAction = value } })
    }
}

enum AdvancedLabels {
    static func action(_ action: AdvancedRule.Action) -> LocalizedStringKey {
        switch action {
        case .direct: return "Direct"
        case .proxy: return "Proxy"
        case .block: return "Block"
        }
    }

    static func kind(_ kind: AdvancedRule.Kind) -> LocalizedStringKey {
        switch kind {
        case .domain: return "Domain"
        case .domainSuffix: return "Domain suffix"
        case .keyword: return "Keyword"
        case .ip: return "IP or network"
        case .geoip: return "Country (GeoIP)"
        }
    }
}
