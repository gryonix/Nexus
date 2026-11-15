import AgentClient
import Foundation
import ServerControl

/// One machine's time zone, host name and time sync
struct HostSystemSettings: Equatable {
    var timeZone = ""
    var hostName = ""
    var ntpEnabled = false
    var ntpSynchronized = false
    var timeZones: [String] = []

    init() {}

    init(_ reply: Gryonixnexusd_V1_SystemSettings) {
        timeZone = reply.timeZone
        hostName = reply.hostName
        ntpEnabled = reply.ntpEnabled
        ntpSynchronized = reply.ntpSynchronized
        timeZones = reply.timeZones
    }
}

@MainActor
final class SystemSettingsModel: ObservableObject {
    @Published private(set) var settings: [SSHHostID: HostSystemSettings] = [:]
    @Published private(set) var errors: [SSHHostID: String] = [:]
    @Published private(set) var busy: Set<SSHHostID> = []

    private let clientFor: (SSHHostID) async throws -> AgentClient

    init(clientFor: @escaping (SSHHostID) async throws -> AgentClient) {
        self.clientFor = clientFor
    }

    static func make(for viewModel: DashboardViewModel) -> SystemSettingsModel {
        SystemSettingsModel { host in
            guard viewModel.deployment.usesAgent, #available(macOS 15.0, *) else { throw AgentError.transport("") }
            let runner = try await viewModel.commandSession()
            return try await AgentConnection.client(deployment: viewModel.deployment, runner: runner, host: host)
        }
    }

    func load(_ hosts: [SSHHostID]) async {
        for host in hosts { await apply(host) { try await $0.systemSettings() } }
    }

    func setTimeZone(_ zone: String, host: SSHHostID) async {
        await apply(host) { try await $0.setTimeZone(zone) }
    }

    func setHostName(_ name: String, host: SSHHostID) async {
        await apply(host) { try await $0.setHostName(name) }
    }

    func setTimeSync(_ enabled: Bool, host: SSHHostID) async {
        await apply(host) { try await $0.setTimeSync(enabled: enabled) }
    }

    private func apply(_ host: SSHHostID,
                       _ call: (AgentClient) async throws -> Gryonixnexusd_V1_SystemSettings) async {
        busy.insert(host)
        defer { busy.remove(host) }
        do {
            settings[host] = HostSystemSettings(try await call(clientFor(host)))
            errors[host] = nil
        } catch {
            fail(host, error)
        }
    }

    private func fail(_ host: SSHHostID, _ error: Error) {
        if settings[host] == nil { return }
        errors[host] = AgentOutdated.describe(error)
    }
}
