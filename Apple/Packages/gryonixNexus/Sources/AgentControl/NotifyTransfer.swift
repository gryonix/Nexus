import AgentClient
import Foundation

/// A server's gryonixPush settings as a small file
public struct NotifyTransfer: Codable, Equatable, Sendable {
    public static let typeTag = "gryonixpush"
    public static let currentVersion = 1

    public struct Checks: Codable, Equatable, Sendable {
        public var raid = true
        public var smart = true
        public var diskSpace = true
        public var diskSpacePercent = 90
        public var services = true
        public var backups = true
        public var agentUpdate = true
        public var operations = false
        public var sshLogins = true
    }

    public enum Failure: Error, Equatable, Sendable {
        case notAPushFile
        case newerVersion
        case unknownChannel
    }

    public var type = NotifyTransfer.typeTag
    public var version = NotifyTransfer.currentVersion
    public var channel: String
    public var relayURL: String
    public var ntfyURL: String
    public var ntfyTopic: String
    public var customChecks: Bool
    public var checks: Checks

    public init(request: Gryonixnexusd_V1_SetNotifySettingsRequest) {
        channel = Self.name(of: request.channel)
        relayURL = request.relayURL
        ntfyURL = request.ntfyURL
        ntfyTopic = request.ntfyTopic
        customChecks = request.customChecks
        checks = Checks(raid: request.checks.raid, smart: request.checks.smart,
                        diskSpace: request.checks.diskSpace,
                        diskSpacePercent: Int(request.checks.diskSpacePercent),
                        services: request.checks.services, backups: request.checks.backups,
                        agentUpdate: request.checks.agentUpdate, operations: request.checks.operations,
                        sshLogins: request.checks.sshLogins)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> NotifyTransfer {
        guard let file = try? JSONDecoder().decode(NotifyTransfer.self, from: data),
              file.type == typeTag else { throw Failure.notAPushFile }
        guard file.version <= currentVersion else { throw Failure.newerVersion }
        guard ["off", "relay", "ntfy"].contains(file.channel) else { throw Failure.unknownChannel }
        return file
    }

    public func applied(to draft: Gryonixnexusd_V1_SetNotifySettingsRequest) -> Gryonixnexusd_V1_SetNotifySettingsRequest {
        var request = draft
        request.channel = Self.channel(named: channel)
        request.relayURL = relayURL
        request.ntfyURL = ntfyURL
        request.ntfyTopic = ntfyTopic
        request.customChecks = customChecks
        if customChecks {
            var wire = Gryonixnexusd_V1_NotifyChecks()
            wire.raid = checks.raid
            wire.smart = checks.smart
            wire.diskSpace = checks.diskSpace
            wire.diskSpacePercent = UInt32(min(max(checks.diskSpacePercent, 50), 99))
            wire.services = checks.services
            wire.backups = checks.backups
            wire.agentUpdate = checks.agentUpdate
            wire.operations = checks.operations
            wire.sshLogins = checks.sshLogins
            request.checks = wire
        }
        return request
    }

    private static func name(of channel: Gryonixnexusd_V1_NotifyChannel) -> String {
        switch channel {
        case .relay: return "relay"
        case .ntfy: return "ntfy"
        default: return "off"
        }
    }

    private static func channel(named name: String) -> Gryonixnexusd_V1_NotifyChannel {
        switch name {
        case "relay": return .relay
        case "ntfy": return .ntfy
        default: return .off
        }
    }
}
