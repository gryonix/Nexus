import Foundation

/// The server's own packages: last run, log and start-up switches
public struct SystemUpdateStatus: Sendable, Equatable {
    public var isRunning = false
    /// Exit code of the last run, nil before any
    public var exitCode: Int?
    public var finished: Date?
    public var needsRestart = false
    public var systemAtStart = false
    public var appsAtStart = false
    public var systemAtStop = false
    public var appsAtStop = false
    /// The updater on the host knows the shutdown switches
    public var offersAtStop = false
    /// All swap the machine has
    public var swapBytes: Int64 = 0
    /// The part that is the app's own swap file
    public var swapFileBytes: Int64 = 0
    /// The system's own timer; nil when the updater predates it
    public var schedule: CommandCatalog.Backups.Schedule?
    /// The host's reboot timer; nil when the updater predates it
    public var rebootSchedule: RebootSchedule?
    public var log: [String] = []

    public init() {}

    /// Reads `gryonixnexus-system-ctl.sh status`
    public static func parse(_ output: String) -> SystemUpdateStatus? {
        guard let marker = output.range(of: "log:\n") ?? output.range(of: "log:") else { return nil }
        var status = SystemUpdateStatus()
        for line in output[..<marker.lowerBound].split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            status.apply(key: parts[0], value: parts[1])
        }
        status.log = output[marker.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.isEmpty && !$0.hasPrefix(SystemUpdate.exitMarker) }
        return status
    }

    private mutating func apply(key: String, value: String) {
        switch key {
        case "state": isRunning = value == "running"
        case "exit": exitCode = Int(value)
        case "finished": finished = Double(value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        case "reboot": needsRestart = value == "yes"
        case "system": systemAtStart = value == "on"
        case "apps": appsAtStart = value == "on"
        case "system_stop": systemAtStop = value == "on"; offersAtStop = true
        case "apps_stop": appsAtStop = value == "on"; offersAtStop = true
        case "swap": swapBytes = Int64(value) ?? 0
        case "swapfile": swapFileBytes = Int64(value) ?? 0
        case "schedule": schedule = CommandCatalog.Backups.Schedule(wrapperArgument: value)
        case "reboot_schedule": rebootSchedule = RebootSchedule(wrapperArgument: value)
        default: break
        }
    }
}

/// When the host restarts by itself
public enum RebootSchedule: Sendable, Equatable {
    case off
    case daily(hour: Int, minute: Int)
    /// Weekday 1 is Monday, 7 is Sunday
    case weekly(weekday: Int, hour: Int, minute: Int)

    public var wrapperArgument: String {
        switch self {
        case .off: return "off"
        case .daily(let hour, let minute): return "daily@\(Self.clock(hour, minute))"
        case .weekly(let weekday, let hour, let minute): return "weekly:\(weekday)@\(Self.clock(hour, minute))"
        }
    }

    public init?(wrapperArgument: String) {
        if wrapperArgument == "off" { self = .off; return }
        let parts = wrapperArgument.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let time = Self.time(parts[1]) else { return nil }
        if parts[0] == "daily" {
            self = .daily(hour: time.hour, minute: time.minute)
        } else if parts[0].hasPrefix("weekly:"), let day = Int(parts[0].dropFirst(7)), (1...7).contains(day) {
            self = .weekly(weekday: day, hour: time.hour, minute: time.minute)
        } else {
            return nil
        }
    }

    private static func clock(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    private static func time(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

/// Commands for the updater the agent puts on each host
public enum SystemUpdate {
    public static let scriptPath = "/opt/gryonixnexus-system-ctl.sh"
    static let exitMarker = "GRYONIXNEXUS_SYSTEM_EXIT:"

    /// What updates when the machine starts
    public enum Part: String, Sendable { case system, apps }

    public static let statusCommand = "sudo -n \(scriptPath) status"
    public static let startCommand = "sudo -n \(scriptPath) start"

    public static func atStartCommand(_ part: Part, on: Bool) -> String {
        "sudo -n \(scriptPath) at-start \(part.rawValue) \(on ? "on" : "off")"
    }

    public static func atStopCommand(_ part: Part, on: Bool) -> String {
        "sudo -n \(scriptPath) at-stop \(part.rawValue) \(on ? "on" : "off")"
    }

    public static func scheduleCommand(_ schedule: CommandCatalog.Backups.Schedule) -> String {
        "sudo -n \(scriptPath) schedule \(schedule.wrapperArgument)"
    }

    public static func rebootScheduleCommand(_ schedule: RebootSchedule) -> String {
        "sudo -n \(scriptPath) reboot-schedule \(schedule.wrapperArgument)"
    }

    /// A swap file of `sizeGB`, or none when nil
    public static func swapCommand(sizeGB: Int?) -> String {
        "sudo -n \(scriptPath) swap \(sizeGB.map(String.init) ?? "off")"
    }

    /// Whether the host lacks the updater or its grant
    public static func isMissing(_ result: ExecResult) -> Bool {
        ServerControlError.stderrAsksForASudoPassword(result.stderr)
            || result.stderr.contains("command not found")
            || result.stderr.contains("No such file")
            || deniedBySudo.contains { result.stderr.contains($0) }
    }

    /// sudo's ways of saying the grant is not there
    private static let deniedBySudo = [
        "I'm afraid I can't do that", "is not allowed to execute", "is not in the sudoers file"
    ]
}

/// Runs the updater on one host
public struct SystemUpdateOperations: Sendable {
    public let runner: any SSHCommandRunner

    public init(runner: any SSHCommandRunner) { self.runner = runner }

    public func status(on host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.statusCommand, on: host)
    }

    public func start(on host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.startCommand, on: host)
    }

    public func setAtStart(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.atStartCommand(part, on: on), on: host)
    }

    public func setAtStop(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.atStopCommand(part, on: on), on: host)
    }

    public func setSchedule(_ schedule: CommandCatalog.Backups.Schedule,
                            host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.scheduleCommand(schedule), on: host)
    }

    public func setRebootSchedule(_ schedule: RebootSchedule, host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.rebootScheduleCommand(schedule), on: host)
    }

    public func setSwap(sizeGB: Int?, host: SSHHostID) async throws -> SystemUpdateStatus {
        try await parsed(SystemUpdate.swapCommand(sizeGB: sizeGB), on: host)
    }

    private func parsed(_ command: String, on host: SSHHostID) async throws -> SystemUpdateStatus {
        let result = try await runner.run(command, on: host, timeout: .seconds(60))
        if !result.succeeded, SystemUpdate.isMissing(result) { throw SystemUpdateError.updaterMissing }
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command, exitCode: result.exitCode, stderr: result.stderr)
        }
        guard let status = SystemUpdateStatus.parse(result.stdout) else {
            throw ServerControlError.parseFailure(command: command, detail: "no status")
        }
        return status
    }
}

public enum SystemUpdateError: Error, Equatable {
    /// The agent on this host predates the updater
    case updaterMissing
}

/// What the agent accepts as a machine's host name
public enum HostNameRules {
    public static func isValid(_ name: String) -> Bool {
        guard (1...63).contains(name.utf8.count), name.first != "-", name.last != "-" else { return false }
        return name.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
    }
}
