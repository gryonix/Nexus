import AgentClient
import Foundation
import SwiftProtobuf

extension DemoAgentState {
    /// The server's alerts: channel, checks and devices
    func notify(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        let prefix = "/gryonixnexusd.v1.Notify/"
        guard path.hasPrefix(prefix) else { return nil }
        switch path.dropFirst(prefix.count) {
        case "GetNotifySettings":
            return notifySettings(machine).demoPayload
        case "SetNotifySettings":
            let asked = try Gryonixnexusd_V1_SetNotifySettingsRequest(serializedBytes: request)
            return changeNotify(machine) { settings in
                settings.channel = asked.channel
                settings.relayURL = asked.relayURL
                settings.ntfyURL = asked.ntfyURL
                settings.ntfyTopic = asked.ntfyTopic
                settings.checks = asked.checks
                settings.language = asked.language
                settings.customChecks = asked.customChecks
            }.demoPayload
        case "RegisterNotifyDevice":
            return changeNotify(machine) { $0.devices += 1 }.demoPayload
        case "UnregisterNotifyDevice":
            return changeNotify(machine) { $0.devices = max(0, $0.devices - 1) }.demoPayload
        default:
            var result = Gryonixnexusd_V1_NotifyTestResult()
            result.ok = true
            return result.demoPayload
        }
    }

    private func notifySettings(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_NotifySettings {
        if let stored = memory(machine).notify { return stored }
        var fresh = Gryonixnexusd_V1_NotifySettings()
        fresh.channel = .off
        fresh.serverID = machine.id.uuidString
        fresh.lastCheckAt = Int64(Date().timeIntervalSince1970)
        return fresh
    }

    private func changeNotify(_ machine: DemoAgentMachine,
                              _ edit: (inout Gryonixnexusd_V1_NotifySettings) -> Void) -> Gryonixnexusd_V1_NotifySettings {
        var next = notifySettings(machine)
        edit(&next)
        var stored = memory(machine)
        stored.notify = next
        write(stored, for: machine)
        return next
    }
}
