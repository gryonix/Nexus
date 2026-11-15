import ServerControl
import ServiceCatalog
import SwiftUI

/// One server's modules, read from and written to its agent
struct ServerModulesView: View {
    let server: Deployment
    let ask: (AppModule, Bool, @escaping () -> Void) -> Void
    @ObservedObject private var modules = ModuleSettings.shared
    @State private var failure: String?
    @State private var loading = true

    var body: some View {
        Form {
            Section {
                ForEach(AppModule.allCases) { module in
                    ModuleToggle(module: module, isOn: modules.isOn(module, server: server.id.uuidString)) { on in
                        ask(module, on) { change(module, on) }
                    }
                }
            } footer: {
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .disabled(loading)
        }
        .screenTitle(server.name)
        .task { await load() }
    }

    private func load() async {
        defer { loading = false }
        guard #available(macOS 15.0, *) else { return }
        do {
            modules.adopt(server: server.id.uuidString, on: try await ServerModules.read(server))
            failure = nil
        } catch ServerModules.Failure.oldAgent {
            failure = UIL10n.string("Update this server's agent to keep modules on it.")
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }

    private func change(_ module: AppModule, _ on: Bool) {
        let set = modules.set(module, on: on, server: server.id.uuidString)
        guard #available(macOS 15.0, *) else { return }
        Task {
            do {
                try await ServerModules.write(server, set)
                failure = nil
            } catch {
                failure = DashboardViewModel.message(for: error)
            }
        }
    }
}
