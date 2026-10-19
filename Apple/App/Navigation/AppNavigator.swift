import Foundation
import ServerControl
import VPNTunnel

/// Cross-section navigation requests
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()

    @Published var openServerID: UUID?

    @Published var requestedTab: AppTab?

    @Published var incomingServerFile: URL?

    @Published var resumeInstall: Deployment?
    /// The repair flow, shown above everything
    @Published var reinstallRequest: ReinstallRequest?

    @Published var reopenInstallResult: Deployment?

    @Published var settingsPage: AppSettingsView.SettingsPage?

    @Published var sectionServer: SectionServer?

    struct SectionServer: Equatable, Sendable {
        let tab: AppTab
        let deploymentID: UUID
    }

    @Published var terminalDirectHostID: UUID?

    @Published var configuratorScenarioID: String?

    /// A one-shot thing the Servers section should do
    @Published var serversAction: ServersAction?

    enum ServersAction: String, Sendable {
        case add, importServer, export
    }

    @Published private(set) var focusTunnel = false

    @Published var configuratorResetToken = UUID()

    private init() {}

    func openServer(_ id: UUID) {
        #if DEBUG
        InstallResetProbe.note("AppNavigator.openServer(\(id))", trace: true)
        #endif
        openServerID = id
    }

    func openServerFile(_ url: URL) {
        incomingServerFile = url
        show(.servers)
    }

    func open(_ destination: AppLink.Destination) {
        switch destination {
        case .server(let id): openServer(id)
        case .tunnel:
            focusTunnel = true
            show(.vpn)
        case .app: break
        case .operation(let id):
            if !RunningOperationsRegistry.shared.present(cardOf: id) { openServer(id) }
        case .job(let id):
            Task { await RunningJobsWatcher.shared.follow(jobID: id) }
        }
    }

    func clearTunnelFocus() {
        focusTunnel = false
    }

    func showServer(_ id: UUID, in tab: AppTab) {
        sectionServer = SectionServer(tab: tab, deploymentID: id)
        show(tab)
    }

    func sectionServer(for tab: AppTab) -> UUID? {
        sectionServer?.tab == tab ? sectionServer?.deploymentID : nil
    }

    func clearSectionServer(for tab: AppTab) {
        if sectionServer?.tab == tab { sectionServer = nil }
    }

    /// Open a directly-added machine in the Terminal section
    func openTerminalHost(_ id: UUID) {
        terminalDirectHostID = id
        show(.terminal)
    }

    /// Show a section
    func show(_ tab: AppTab) {
        requestedTab = tab
    }

    /// Open one configurator scenario, switching to that section first
    func showScenario(_ id: String) {
        configuratorScenarioID = id
        show(.configurator)
    }

    /// Ask the Servers section to add, import or export
    func askServers(_ action: ServersAction) {
        serversAction = action
        show(.servers)
    }

    /// Show one page inside Settings, switching to the section first
    func showSettingsPage(_ page: AppSettingsView.SettingsPage) {
        settingsPage = page
        show(.settings)
    }

    /// Reset the Configurator section back to its initial screen
    func resetConfigurator() {
        #if DEBUG
        InstallResetProbe.note("AppNavigator.resetConfigurator()", trace: true)
        #endif
        configuratorResetToken = UUID()
    }
}
