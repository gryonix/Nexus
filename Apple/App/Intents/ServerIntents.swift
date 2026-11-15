import AppIntents
import Foundation
import ServerControl
import VPNTunnel

struct ServerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Server status"
    static var description = IntentDescription("Says whether a server is online, its load and its problems.")
    static var openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let reading = FleetSnapshotStore().read()?.servers.first { $0.id == server.id }
        let report = ServerStatusReport(name: server.name, server: reading)
        return .result(value: report.sentence,
                       dialog: IntentDialog(stringLiteral: report.sentence),
                       view: ServerStatusSnippet(report: report))
    }
}

struct OpenServerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open server"
    static var description = IntentDescription("Opens the app on a server.")
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.openServer(server.id)
        return .result()
    }
}

struct RestartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart service"
    static var description = IntentDescription("Restarts a service on a server.")
    static var openAppWhenRun = false

    @Parameter(title: "Service")
    var service: ServiceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await confirm(UIL10n.string("Restart %@ on %@?", service.name, service.serverName))
        let message = try await ServicePowerRunner.run(.restart, on: service)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Start service"
    static var description = IntentDescription("Starts a service on a server.")
    static var openAppWhenRun = false

    @Parameter(title: "Service")
    var service: ServiceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ServicePowerRunner.run(.start, on: service)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop service"
    static var description = IntentDescription("Stops a service on a server.")
    static var openAppWhenRun = false

    @Parameter(title: "Service")
    var service: ServiceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await confirm(UIL10n.string("Stop %@ on %@?", service.name, service.serverName))
        let message = try await ServicePowerRunner.run(.stop, on: service)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

extension AppIntent {
    func confirm(_ question: String) async throws {
        if #available(iOS 18.0, macOS 15.0, *) {
            try await requestConfirmation(dialog: IntentDialog(stringLiteral: question))
        } else {
            try await requestConfirmation()
        }
    }
}
