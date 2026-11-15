import Foundation
import ServerControl
import ServiceCatalog
import VPNTunnel

/// Cross-section navigation requests
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()

    @Published var openServerID: UUID?

    @Published var requestedTab: AppTab?

    /// Changes each time the Servers tab is opened
    @Published private(set) var serversTabOpened = UUID()

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

    /// The section a server should open on
    @Published private(set) var serverTab: ServerTab?

    struct ServerTab: Equatable, Sendable {
        let deploymentID: UUID
        let tab: DashboardTab
    }

    /// The service whose log a server should open
    private var serverService: (deploymentID: UUID, service: ServiceID)?

    /// The alert a server should show
    private var serverAlert: (deploymentID: UUID, card: AlertCard)?

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

    /// Opens a server on one of its sections
    func openServer(_ id: UUID, at tab: DashboardTab, service: ServiceID? = nil) {
        serverService = service.map { (id, $0) }
        serverTab = ServerTab(deploymentID: id, tab: tab)
        openServer(id)
    }

    /// Opens a server with a tapped alert over it
    func openServer(_ id: UUID, at tab: DashboardTab, showing card: AlertCard) {
        serverAlert = (id, card)
        openServer(id, at: tab)
    }

    func takeServerAlert(for id: UUID) -> AlertCard? {
        guard let asked = serverAlert, asked.deploymentID == id else { return nil }
        serverAlert = nil
        return asked.card
    }

    func takeServerService(for id: UUID) -> ServiceID? {
        guard let asked = serverService, asked.deploymentID == id else { return nil }
        serverService = nil
        return asked.service
    }

    func takeServerTab(for id: UUID) -> DashboardTab? {
        guard let asked = serverTab, asked.deploymentID == id else { return nil }
        serverTab = nil
        return asked.tab
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

    func noteServersTabOpened() {
        serversTabOpened = UUID()
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
