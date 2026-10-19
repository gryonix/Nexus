import Foundation
import gryonixNexusCore

public enum AdminLockdownState: Sendable, Hashable {
    case off
    case all
    case only(Set<String>)

    /// Whether the given vhost is currently guarded
    public func guards(_ host: String) -> Bool {
        switch self {
        case .off: return false
        case .all: return true
        case .only(let hosts): return hosts.contains(host)
        }
    }

    public var isActive: Bool { self != .off }
}

/// One-shot status probes and simple restarts
public struct StatusOperations: Sendable {
    private let runner: any SSHCommandRunner
    private let config: DashboardConfig

    public init(runner: any SSHCommandRunner, config: DashboardConfig) {
        self.runner = runner
        self.config = config
    }

    public func macAddress(on host: SSHHostID) async throws -> String? {
        let output = try await runSucceeding(CommandCatalog.defaultRouteMACAddress, on: host,
                                             timeout: config.quickTimeout)
        return WakeOnLAN.normalised(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The MAC and broadcast address Wake on LAN needs
    public func wakeInfo(on host: SSHHostID) async throws -> (mac: String, broadcast: String?)? {
        let output = try await runSucceeding(WakeOnLAN.readCommand, on: host, timeout: config.quickTimeout)
        return WakeOnLAN.parseRead(output)
    }

    public func sendWakeOnLAN(mac: String, broadcast: String, from host: SSHHostID) async throws {
        guard let command = WakeOnLAN.command(mac: mac, broadcast: broadcast) else {
            throw ServerControlError.parseFailure(command: "wake-on-lan",
                                                  detail: "not a MAC address and a broadcast address")
        }
        _ = try await runSucceeding(command, on: host, timeout: config.quickTimeout)
    }

    public func ipForwarding(on host: SSHHostID) async throws -> Bool {
        let output = try await runSucceeding(CommandCatalog.ipForwardingCheck, on: host,
                                             timeout: config.quickTimeout)
        return try SysctlParser.parseIPForwarding(output)
    }

    /// Pings the VPS public address from the VPS itself
    public func pingVPS() async throws -> PingResult {
        let result = try await runner.run(CommandCatalog.pingSelf(vpsHost: config.vpsHost),
                                          on: .vps, timeout: config.quickTimeout)
        return try PingParser.parse(result.stdout)
    }

    /// The three VPS-side General probes in a single round-trip
    public func generalVPSStatus() async throws -> GeneralVPSStatus {
        let result = try await runner.run(
            CommandCatalog.generalProbe(vpsHost: config.vpsHost,
                                        homeWGAddress: config.homeWGAddress),
            on: .vps, timeout: config.quickTimeout
        )
        let parts = result.stdout.components(separatedBy: CommandCatalog.generalProbeSeparator)
        guard parts.count == 3 else {
            throw ServerControlError.parseFailure(command: "general probe",
                                                  detail: "expected three sections")
        }
        return GeneralVPSStatus(forwarding: try SysctlParser.parseIPForwarding(parts[0]),
                                selfPing: try PingParser.parse(parts[1]),
                                tunnelPing: try PingParser.parse(parts[2]))
    }

    public func pingTunnel() async throws -> PingResult {
        let result = try await runner.run(
            CommandCatalog.pingTunnel(homeWGAddress: config.homeWGAddress),
            on: .vps, timeout: config.quickTimeout
        )
        return try PingParser.parse(result.stdout)
    }

    public func wgStatus(on host: SSHHostID) async throws -> WGStatus {
        let output = try await runSucceeding(CommandCatalog.wgShow, on: host,
                                             timeout: config.quickTimeout)
        return try WGShowParser.parse(output)
    }

    public func disk(on host: SSHHostID) async throws -> [DiskMount] {
        let output = try await runSucceeding(CommandCatalog.disk, on: host,
                                             timeout: config.quickTimeout)
        return try DFParser.parse(output)
    }

    public func memory(on host: SSHHostID) async throws -> MemoryUsage {
        let output = try await runSucceeding(CommandCatalog.memory, on: host,
                                             timeout: config.quickTimeout)
        return try FreeParser.parse(output)
    }

    /// Whether admin panels are currently VPN-only
    public func adminLockdownStatus(on host: SSHHostID) async throws -> AdminLockdownState {
        let output = try await runSucceeding(CommandCatalog.AdminLockdown.status, on: host,
                                             timeout: config.quickTimeout)
        return Self.parseLockdownAnswer(output)
    }

    public func setAdminLockdown(_ enabled: Bool, on host: SSHHostID) async throws -> AdminLockdownState {
        let command = enabled ? CommandCatalog.AdminLockdown.on : CommandCatalog.AdminLockdown.off
        let output = try await runSucceeding(command, on: host, timeout: config.restartTimeout)
        return Self.parseLockdownAnswer(output)
    }

    /// Guards only the given vhosts
    public func setAdminLockdown(hosts: [String], on host: SSHHostID) async throws -> AdminLockdownState {
        if hosts.isEmpty { return try await setAdminLockdown(false, on: host) }
        let invalid = hosts.filter { !CommandCatalog.AdminLockdown.isValidHost($0) }
        guard invalid.isEmpty else {
            throw ServerControlError.commandFailed(
                command: "lockdown", exitCode: nil,
                stderr: "These names cannot be guarded: \(invalid.joined(separator: ", ")). Nothing was changed.")
        }
        let output = try await runSucceeding(CommandCatalog.AdminLockdown.only(hosts: hosts),
                                             on: host, timeout: config.restartTimeout)
        return Self.parseLockdownAnswer(output)
    }

    static func parseLockdownAnswer(_ output: String) -> AdminLockdownState {
        let last = output.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces) ?? ""
        if last == "on" { return .all }
        if last.hasPrefix("only ") {
            let hosts = last.dropFirst("only ".count)
                .split(separator: " ").map(String.init)
                .filter(CommandCatalog.AdminLockdown.isValidHost)
            return hosts.isEmpty ? .off : .only(Set(hosts))
        }
        return .off
    }

    public func controlContainer(_ action: CommandCatalog.Containers.Action,
                                 name: String, on host: SSHHostID) async throws {
        _ = try await runSucceeding(CommandCatalog.Containers.control(action, container: name),
                                    on: host, timeout: config.restartTimeout)
    }

    public func restartSSHD(on host: SSHHostID) async throws {
        _ = try await runSucceeding(CommandCatalog.restartSSHD, on: host,
                                    timeout: config.restartTimeout)
    }

    /// Reboots a host
    public func reboot(on host: SSHHostID) async throws {
        try await runner.fireAndForget(CommandCatalog.rebootHost, on: host)
    }

    public func powerOff(on host: SSHHostID) async throws {
        _ = try await runner.run("true", on: host, timeout: .seconds(15))
        let result: ExecResult
        do {
            result = try await runner.run(CommandCatalog.powerOffHost, on: host, timeout: .seconds(20))
        } catch {
            return
        }
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: CommandCatalog.powerOffHost,
                                                    exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Plain awaited WireGuard restart — only safe on the VPS
    public func restartWireGuardVPS() async throws {
        _ = try await runSucceeding(CommandCatalog.restartWireGuard(interface: config.wgInterface),
                                    on: .vps, timeout: config.restartTimeout)
    }

    private func runSucceeding(_ command: String, on host: SSHHostID,
                               timeout: Duration) async throws -> String {
        let result = try await runner.run(command, on: host, timeout: timeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command,
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return result.stdout
    }
}
