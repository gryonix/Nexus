import AgentClient
import Foundation
import SwiftProtobuf

actor DemoSystemSettingsStore {
    static let shared = DemoSystemSettingsStore()

    private static let zones = ["Africa/Cairo", "America/New_York", "Asia/Tokyo", "Europe/Berlin",
                                "Europe/Kyiv", "Europe/London", "Europe/Moscow", "UTC"]
    private var settings: [UUID: Gryonixnexusd_V1_SystemSettings] = [:]

    func answer(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        var current = settings[machine.id] ?? Self.initial(for: machine)
        switch path {
        case "/gryonixnexusd.v1.Control/GetSystemSettings":
            break
        case "/gryonixnexusd.v1.Control/SetTimeZone":
            current.timeZone = try Gryonixnexusd_V1_SetTimeZoneRequest(serializedBytes: request).timeZone
        case "/gryonixnexusd.v1.Control/SetHostName":
            current.hostName = try Gryonixnexusd_V1_SetHostNameRequest(serializedBytes: request).hostName
        case "/gryonixnexusd.v1.Control/SetTimeSync":
            current.ntpEnabled = try Gryonixnexusd_V1_SetTimeSyncRequest(serializedBytes: request).enabled
            current.ntpSynchronized = current.ntpEnabled
        default:
            return nil
        }
        settings[machine.id] = current
        return try current.serializedBytes()
    }

    private static func initial(for machine: DemoAgentMachine) -> Gryonixnexusd_V1_SystemSettings {
        var value = Gryonixnexusd_V1_SystemSettings()
        value.timeZone = "Europe/Berlin"
        value.hostName = machine.deployment.name.lowercased().filter { $0.isLetter || $0.isNumber }
        if value.hostName.isEmpty { value.hostName = "orion" }
        value.ntpEnabled = true
        value.ntpSynchronized = true
        value.timeZones = zones
        return value
    }
}
