import Foundation
import Crypto
import Citadel
import AgentClient
import AgentClientSSH
import AgentControl
import ServerControl
import ServiceCatalog

struct SmokeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Pass/fail ledger
final class Report {
    private var failures: [String] = []
    private var passes = 0

    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        let suffix = detail.isEmpty ? "" : "  — \(detail)"
        if ok {
            passes += 1
            print("✓ \(name)\(suffix)")
        } else {
            failures.append(name)
            print("✗ \(name)\(suffix)")
        }
    }

    func note(_ text: String) { print("· \(text)") }

    func section(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            check("\(name) section completed", false, "threw \(error)")
        }
    }

    /// Non-blocking observation: recorded and printed, never fails the run
    func observe(_ name: String, _ detail: String) { print("◦ \(name)  — \(detail)") }

    func finish() -> Never {
        print("── \(passes) passed, \(failures.count) failed ──")
        for failure in failures { print("   FAILED: \(failure)") }
        exit(failures.isEmpty ? 0 : 1)
    }
}

func rpcCode(_ error: Error?) -> String? {
    guard case .rpc(let code, _)? = error as? AgentError else { return nil }
    return code
}

func rpcMessage(_ error: Error?) -> String {
    guard let error else { return "" }
    guard case .rpc(_, let message)? = error as? AgentError else { return "\(error)" }
    return message
}

@available(macOS 15.0, *)
func phase1(_ agent: AgentClient, client: SSHClient, bridge: String, report: Report) async throws {
    let state = try await agent.getState()
    report.check("GetState", !state.host.hostname.isEmpty,
                 "\(state.host.hostname) · \(state.host.osPrettyName) · \(state.host.arch) · agent \(state.agentVersion)")

    let discovered = try await agent.discover()
    let services = discovered.services.map { "\($0.id)(\($0.containers.count))" }.joined(separator: ", ")
    report.check("Discover", !discovered.services.isEmpty, "[\(services)]  notes: \(discovered.notes)")

    var samples = 0
    for try await sample in agent.hostMetrics(intervalSeconds: 1) {
        let memPct = sample.memTotalBytes > 0 ? sample.memUsedBytes * 100 / sample.memTotalBytes : 0
        report.note(String(format: "metric: cpu %.1f%% · mem %lld%% · %d mounts",
                           sample.cpuPercent, memPct, sample.mounts.count))
        samples += 1
        if samples == 2 { break }
    }
    report.check("HostMetrics streams", samples == 2, "\(samples) samples")

    var codeOutput = ""
    let codeCommand = bridge.replacingOccurrences(of: " bridge", with: " pair-code")
    for try await chunk in try await client.executeCommandStream(codeCommand) {
        if case .stdout(let buffer) = chunk { codeOutput += String(buffer: buffer) }
    }
    guard let code = PairingCode.parse(codeOutput) else {
        throw SmokeError("could not parse a pairing code from: \(codeOutput.debugDescription)")
    }
    let device = try await agent.pair(code: code,
                                      devicePublicKey: "agent-smoke-test-key",
                                      label: "agent-smoke")
    report.check("Pair", !device.id.isEmpty, "device \(device.id) · \(device.label) · scopes \(device.scopes)")
    let revoked = try await agent.revoke(deviceID: device.id)
    report.check("Revoke", revoked, "smoke device removed")
}

@available(macOS 15.0, *)
func drain(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_ServiceOperationEvent, Error>)
async -> (events: [Gryonixnexusd_V1_ServiceOperationEvent], error: Error?) {
    var events: [Gryonixnexusd_V1_ServiceOperationEvent] = []
    do {
        for try await event in stream { events.append(event) }
        return (events, nil)
    } catch {
        return (events, error)
    }
}

@available(macOS 15.0, *)
func describe(_ events: [Gryonixnexusd_V1_ServiceOperationEvent]) -> String {
    events.map { event in
        switch event.phase {
        case .started: return "started(\(event.projects.joined(separator: "+")))"
        case .progress: return "progress"
        case .completed: return "completed"
        default: return "?"
        }
    }.joined(separator: " → ")
}

@available(macOS 15.0, *)
func phase2(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    let installed = env["AGENT_INSTALLED"] ?? "vaultwarden"
    let absent = env["AGENT_ABSENT"] ?? "gitlab"
    try await checkServiceStatus(agent, installed: installed, absent: absent, report: report)
    await checkControlRefusals(agent, installed: installed, absent: absent, report: report)
    try await checkControlLifecycle(agent, installed: installed, report: report)
    try await checkVPNAggregate(agent, report: report)
    try await checkClientHangup(agent, env: env, report: report)
    await checkMidStreamFailure(agent, env: env, report: report)
}

/// ServiceStatus: installed, known but absent, and unknown.
@available(macOS 15.0, *)
func checkServiceStatus(_ agent: AgentClient, installed: String, absent: String,
                        report: Report) async throws {
    let live = try await agent.serviceStatus(serviceID: installed)
    report.check("ServiceStatus(\(installed)) reports an installed service",
                 live.installed && !live.service.containers.isEmpty,
                 "status=\(live.service.status) version='\(live.service.version)' " +
                 "containers=\(live.service.containers.map { "\($0.name):\($0.state)" })")

    let missing = try await agent.serviceStatus(serviceID: absent)
    report.check("ServiceStatus(\(absent)) — known but not installed is a RESULT, not an error",
                 !missing.installed && missing.service.containers.isEmpty && !missing.service.displayName.isEmpty,
                 "installed=\(missing.installed) display='\(missing.service.displayName)'")

    do {
        _ = try await agent.serviceStatus(serviceID: "no-such-service")
        report.check("ServiceStatus(unknown id) is refused", false, "it answered instead")
    } catch {
        report.check("ServiceStatus(unknown id) is refused", rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }
}

/// ControlService refusals open no stream.
@available(macOS 15.0, *)
func checkControlRefusals(_ agent: AgentClient, installed: String, absent: String,
                          report: Report) async {
    for (label, id, expected) in [("unknown id", "no-such-service", "invalid_argument"),
                                  ("not installed here", absent, "not_found")] {
        let (events, error) = await drain(agent.controlService(serviceID: id, action: .restart))
        report.check("ControlService(\(label)) fails before acting, with no events",
                     events.isEmpty && rpcCode(error) == expected,
                     "events=\(events.count) \(rpcCode(error) ?? "none"): \(rpcMessage(error))")
    }
    let (unspecEvents, unspecError) = await drain(agent.controlService(serviceID: installed, action: .unspecified))
    report.check("ControlService(action unset) is refused, not defaulted",
                 unspecEvents.isEmpty && rpcCode(unspecError) == "invalid_argument",
                 "events=\(unspecEvents.count) \(rpcCode(unspecError) ?? "none")")
}

/// Restart, stop and start: event shape and container state.
@available(macOS 15.0, *)
func checkControlLifecycle(_ agent: AgentClient, installed: String, report: Report) async throws {
    let (restart, restartError) = await drain(agent.controlService(serviceID: installed, action: .restart))
    report.check("ControlService(restart) streams STARTED … COMPLETED",
                 restartError == nil && restart.first?.phase == .started && restart.last?.phase == .completed,
                 "\(describe(restart))  error=\(restartError.map { "\($0)" } ?? "none")")
    report.check("STARTED names the compose projects it is about to touch",
                 !(restart.first?.projects.isEmpty ?? true),
                 "projects=\(restart.first?.projects ?? [])")
    report.check("COMPLETED carries a freshly re-read status",
                 restart.last?.hasService == true && !(restart.last?.service.containers.isEmpty ?? true),
                 "status=\(restart.last?.service.status.rawValue ?? -1) " +
                 "containers=\(restart.last?.service.containers.map { "\($0.name):\($0.state)" } ?? [])")

    let (stop, stopError) = await drain(agent.controlService(serviceID: installed, action: .stop))
    let stopped = stop.last
    report.check("ControlService(stop) completes",
                 stopError == nil && stopped?.phase == .completed, describe(stop))
    let afterStop = try await agent.serviceStatus(serviceID: installed)
    report.check("stop is `compose stop`, never `down` — the containers still exist",
                 afterStop.installed && !afterStop.service.containers.isEmpty
                 && afterStop.service.containers.allSatisfy { $0.state != "running" },
                 "containers=\(afterStop.service.containers.map { "\($0.name):\($0.state)" })")
    report.check("COMPLETED after stop reports the stopped state",
                 stopped?.service.status == .stopped,
                 "status=\(stopped?.service.status.rawValue ?? -1)")

    let namesBefore = Set(afterStop.service.containers.map(\.name))
    let (start, startError) = await drain(agent.controlService(serviceID: installed, action: .start))
    let started = start.last
    report.check("ControlService(start) completes running",
                 startError == nil && started?.service.status == .running,
                 "\(describe(start)) status=\(started?.service.status.rawValue ?? -1)")
    report.check("start brought back the same containers",
                 Set(started?.service.containers.map(\.name) ?? []) == namesBefore,
                 "\(namesBefore) → \(Set(started?.service.containers.map(\.name) ?? []))")
}

@available(macOS 15.0, *)
func checkVPNAggregate(_ agent: AgentClient, report: Report) async throws {
    let vpn = try await agent.serviceStatus(serviceID: "vpn")
    if vpn.installed {
        let (vpnEvents, vpnError) = await drain(agent.controlService(serviceID: "vpn", action: .restart))
        let projects = vpnEvents.first?.projects ?? []
        let containers = vpn.service.containers.map(\.name)
        let onlyPanel = containers.allSatisfy { $0.contains("vpnpanel") }
        report.check("vpn resolves to the aggregate (panel + every protocol as one service)",
                     vpnError == nil && !projects.isEmpty && (onlyPanel || projects.count >= 2),
                     "projects=\(projects) containers=\(containers)"
                        + (onlyPanel ? " (panel-only host: one project is correct)" : ""))
    } else {
        report.note("no vpn projects on this host — aggregate not exercised")
    }
}

@available(macOS 15.0, *)
func checkClientHangup(_ agent: AgentClient, env: [String: String], report: Report) async throws {
    if let slow = env["AGENT_SLOW"] {
        _ = await drain(agent.controlService(serviceID: slow, action: .start))
        let stream = agent.controlService(serviceID: slow, action: .stop)
        let watcher = Task {
            for try await event in stream where event.phase == .started { break }
        }
        _ = try? await watcher.value
        report.note("hung up on \(slow) right after STARTED; waiting for the stop to finish anyway")
        try await Task.sleep(nanoseconds: 35_000_000_000)
        let after = try await agent.serviceStatus(serviceID: slow)
        report.check("a command already running survives the client hanging up",
                     after.service.status == .stopped,
                     "status=\(after.service.status) containers=\(after.service.containers.map { "\($0.name):\($0.state)" })")
        _ = await drain(agent.controlService(serviceID: slow, action: .start))
    } else {
        report.note("AGENT_SLOW unset — the client-hangup path is not exercised")
    }
}

@available(macOS 15.0, *)
func checkMidStreamFailure(_ agent: AgentClient, env: [String: String], report: Report) async {
    if let failing = env["AGENT_FAILING"] {
        let (events, error) = await drain(agent.controlService(serviceID: failing, action: .start))
        report.check("a mid-run failure ends the stream with an error",
                     error != nil, "error=\(error.map { "\(rpcCode($0) ?? "?"): \(rpcMessage($0))" } ?? "none")")
        report.check("…but only AFTER a COMPLETED event carrying the post-action status",
                     events.last?.phase == .completed && events.last?.hasService == true,
                     describe(events))
    } else {
        report.note("AGENT_FAILING unset — the mid-stream failure path is not exercised")
    }
}

/// A minimal `SSHCommandRunner` over the harness's own connection
@available(macOS 15.0, *)
struct SmokeSSHRunner: SSHCommandRunner {
    let client: SSHClient

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        var stdout = ""
        var stderr = ""
        for try await chunk in try await client.executeCommandStream(command) {
            switch chunk {
            case .stdout(let buffer): stdout += String(buffer: buffer)
            case .stderr(let buffer): stderr += String(buffer: buffer)
            }
        }
        return ExecResult(exitCode: 0, stdout: stdout, stderr: stderr)
    }

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {}

    func disconnect() async {}
}

/// What the metrics board reads, against a live collector
@available(macOS 15.0, *)
func metricsBoardSection(_ agent: AgentClient, client: SSHClient, report: Report) async throws {
    let ranges: [(String, TimeInterval, MetricsHistoryBucket)] = [
        ("10m", 600, .tenSeconds),
        ("1h", 3_600, .oneMinute),
        ("3h", 3 * 3_600, .oneMinute),
        ("10h", 10 * 3_600, .tenMinutes),
        ("1d", 86_400, .tenMinutes),
        ("1w", 7 * 86_400, .oneHour),
        ("1mo", 30 * 86_400, .oneDay),
        ("1y", 365 * 86_400, .oneWeek),
    ]

    let selected = Set(ranges.map(\.2))
    let unreachable = MetricsHistoryBucket.allCases.filter { !selected.contains($0) }
    report.check("every bucket the collector maintains is selectable by some period",
                 unreachable.isEmpty,
                 unreachable.isEmpty ? "\(selected.count) buckets"
                                     : "never read: \(unreachable.map(\.rawValue).joined(separator: " "))")

    var uptime: TimeInterval = 0
    for try await chunk in try await client.executeCommandStream("cat /proc/uptime") {
        if case .stdout(let buffer) = chunk {
            uptime = Double(String(buffer: buffer).split(separator: " ").first ?? "0") ?? 0
        }
    }
    report.note("host uptime \(Int(uptime / 3600)) h — periods needing more history than that are reported, not failed")

    let source = AgentMetricsHistory(client: agent, gate: AgentChannelGate())
    for (label, span, bucket) in ranges {
        let points = try await source.history(bucket: bucket, on: .home)
        let cutoff = Date().addingTimeInterval(-span)
        let inWindow = points.filter { $0.date >= cutoff }

        let enoughHistory = uptime >= span || uptime >= bucket.pointInterval * 2
        if enoughHistory {
            report.check("period \(label) has something to draw from the \(bucket.rawValue) bucket",
                         inWindow.count >= 2,
                         "\(inWindow.count) points in the last \(Int(span))s of \(points.count) total")
        } else {
            report.note("period \(label): the host has not been up long enough to fill the " +
                        "\(bucket.rawValue) bucket (\(inWindow.count) points) — not a failure")
        }

        report.check("period \(label) resolves to a bucket fine enough to fill it",
                     bucket.pointInterval * 4 <= span,
                     "\(bucket.rawValue) every \(Int(bucket.pointInterval))s across \(Int(span))s")
    }

    let ssh = MetricsHistoryProbe(runner: SmokeSSHRunner(client: client), timeout: .seconds(30))
    let viaSSH = try await ssh.history(bucket: .oneMinute, on: .home)
    let viaAgent = try await source.history(bucket: .oneMinute, on: .home)
    report.check("the SSH reader returns the same bucket the agent does",
                 !viaSSH.isEmpty && abs(viaSSH.count - viaAgent.count) <= 2,
                 "ssh \(viaSSH.count) rows, agent \(viaAgent.count) rows")

    if let sshLast = viaSSH.last, let agentLast = viaAgent.last {
        report.check("both routes agree on the newest sample",
                     abs(sshLast.date.timeIntervalSince(agentLast.date)) <= 60,
                     "ssh \(sshLast.date), agent \(agentLast.date)")
        let cpu = sshLast.cpuPercent ?? 0
        report.check("the newest sample carries plausible values",
                     cpu >= 0 && cpu <= 100 && sshLast.memTotalBytes > 0
                         && sshLast.memUsedBytes <= sshLast.memTotalBytes,
                     "cpu \(cpu)%, memory \(sshLast.memUsedBytes)/\(sshLast.memTotalBytes) bytes")
    }
}

/// The history slice's live evidence
@available(macOS 15.0, *)
func historySection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    let liveBucket = env["AGENT_HISTORY_BUCKET"] ?? "10s"

    var answered: [String] = []
    for bucket in MetricsHistoryBucket.allCases {
        do {
            let response = try await agent.metricsHistory(bucket: bucket.rawValue)
            guard response.bucket == bucket.rawValue else { continue }
            answered.append("\(bucket.rawValue):\(response.points.count)")
        } catch {
            report.note("bucket \(bucket.rawValue) failed: \(rpcMessage(error))")
        }
    }
    report.check("every collector bucket answers, echoing its own name",
                 answered.count == MetricsHistoryBucket.allCases.count, "[\(answered.joined(separator: " "))]")

    for hostile in ["30s", "10s.csv", "../../etc/shadow", "/etc/shadow", ""] {
        do {
            _ = try await agent.metricsHistory(bucket: hostile)
            report.check("MetricsHistory(\(hostile.isEmpty ? "empty" : hostile)) is refused", false,
                         "it answered instead")
        } catch {
            report.check("MetricsHistory(\(hostile.isEmpty ? "empty" : hostile)) is refused",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(90))")
        }
    }

    let live = try await agent.metricsHistory(bucket: liveBucket)
    guard !live.points.isEmpty else {
        report.note("no rows in the \(liveBucket) bucket on this host — the row-shape checks are skipped")
        return
    }
    // Rows arrive oldest-first and carry the collector's own values.
    let ordered = zip(live.points, live.points.dropFirst()).allSatisfy { $0.at <= $1.at }
    report.check("history rows arrive oldest first", ordered,
                 "\(live.points.count) rows, \(Date(timeIntervalSince1970: Double(live.points[0].at) / 1000)) → " +
                 "\(Date(timeIntervalSince1970: Double(live.points[live.points.count - 1].at) / 1000))")
    let last = live.points[live.points.count - 1]
    report.check("a row carries the gauges the chart draws",
                 last.memTotalBytes > 0 && last.diskTotalBytes > 0,
                 String(format: "mem %lld/%lld · disk %lld/%lld · load1 %.2f · cpu %@ · temp %@",
                        last.memUsedBytes, last.memTotalBytes, last.diskUsedBytes, last.diskTotalBytes,
                        last.load1,
                        last.hasCpuPercent ? String(format: "%.1f%%", last.cpuPercent) : "absent",
                        last.hasTemperatureCelsius ? String(format: "%.1f°C", last.temperatureCelsius) : "absent"))

    let limited = try await agent.metricsHistory(bucket: liveBucket, limit: 3)
    let after = try await agent.metricsHistory(bucket: liveBucket)
    let newestAfter = after.points.last?.at ?? -1
    let limitedNewest = limited.points.last?.at ?? -1
    let isTail = Array(after.points.suffix(limited.points.count)).map(\.at) == limited.points.map(\.at)
    report.check("limit returns the NEWEST rows",
                 limited.points.count <= 3
                     && limitedNewest >= last.at && limitedNewest <= newestAfter
                     && (isTail || limitedNewest < newestAfter),
                 "\(limited.points.count) rows, newest \(limitedNewest) within [\(last.at), \(newestAfter)]")

    let cutoff = Date(timeIntervalSince1970: Double(last.at) / 1000).addingTimeInterval(-1)
    let windowed = try await agent.metricsHistory(bucket: liveBucket, since: cutoff)
    report.check("since drops everything older, on the server",
                 windowed.points.count < live.points.count || live.points.count == 1,
                 "\(live.points.count) rows → \(windowed.points.count)")

    let empty = try await agent.metricsHistory(bucket: liveBucket, since: Date().addingTimeInterval(86_400))
    report.check("a window with nothing in it is empty history, not a failure",
                 empty.points.isEmpty, "\(empty.points.count) rows")

    let source = AgentMetricsHistory(client: agent, gate: AgentChannelGate())
    let bucket = MetricsHistoryBucket(rawValue: liveBucket) ?? .tenSeconds
    let points = try await source.history(bucket: bucket, on: .home)
    report.check("AgentMetricsHistory — the app's own seam — maps the rows",
                 points.count == live.points.count && points.last?.memTotalBytes == last.memTotalBytes,
                 "\(points.count) points, last mem \(points.last?.memTotalBytes ?? -1)")
    let absentTemperatures = live.points.filter { !$0.hasTemperatureCelsius }.count
    report.check("an absent temperature stays nil through the mapping",
                 points.filter { $0.temperatureCelsius == nil }.count == absentTemperatures,
                 "\(absentTemperatures) of \(live.points.count) rows have no temperature")
}

@available(macOS 15.0, *)
func backupSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let target = env["AGENT_BACKUP_SERVICE"] else {
        report.note("AGENT_BACKUP_SERVICE unset — the backup section is not exercised")
        return
    }
    let list = try await checkBackupListing(agent, target: target, report: report)
    try await checkBackupRefusals(agent, target: target, absent: env["AGENT_BACKUP_ABSENT"] ?? "gitlab",
                                  list: list, report: report)
    let estimate = try await agent.estimateBackup(serviceID: target)
    report.check("EstimateBackup answers in bytes, so the app decides what \"too big\" means",
                 estimate.freeBytes > 0,
                 "data \(estimate.dataBytes) B · free \(estimate.freeBytes) B")
    guard let service = ServiceRegistry.all.first(where: { AgentServiceMapping.agentID(for: $0.id) == target })
    else {
        report.note("no catalog service maps to \(target) — the app-seam checks are skipped")
        return
    }
    let backups = AgentBackupOperations(client: agent, gate: AgentChannelGate())
    try await checkBackupSeam(backups, service: service, list: list, estimate: estimate, report: report)
    if let failing = env["AGENT_BACKUP_FAILING"] {
        await checkFailingBackup(agent, backups: backups, failing: failing, report: report)
    } else {
        report.note("AGENT_BACKUP_FAILING unset — the mid-run failure path is not exercised")
    }
    guard env["AGENT_BACKUP_RUN"] == "1" else {
        report.note("AGENT_BACKUP_RUN unset — no archive is written by this run")
        return
    }
    try await checkRealBackup(agent, target: target, list: list, env: env, report: report)
}

@available(macOS 15.0, *)
func checkBackupListing(_ agent: AgentClient, target: String,
                        report: Report) async throws -> Gryonixnexusd_V1_BackupList {
    let list = try await agent.listBackups(serviceID: target)
    report.check("ListBackups resolves the directory from the wrapper on the host",
                 list.directory.hasPrefix("/"),
                 "\(list.directory) · \(list.archives.count) archives")
    report.check("every listed archive carries an absolute path, a size and a time",
                 list.archives.allSatisfy { $0.path.hasPrefix(list.directory + "/") && $0.modifiedAt > 0 },
                 list.archives.map { "\($0.name):\($0.sizeBytes)B" }.joined(separator: " "))
    report.check("the upload staging directory is not listed as a backup",
                 !list.archives.contains { $0.name == "incoming" },
                 list.archives.map(\.name).joined(separator: " "))
    let ordered = zip(list.archives, list.archives.dropFirst()).allSatisfy { $0.modifiedAt >= $1.modifiedAt }
    report.check("the listing arrives newest first", ordered,
                 list.archives.map { "\($0.modifiedAt)" }.joined(separator: " "))
    return list
}

@available(macOS 15.0, *)
func checkBackupRefusals(_ agent: AgentClient, target: String, absent: String,
                         list: Gryonixnexusd_V1_BackupList, report: Report) async throws {
    for hostile in ["nope", "\(target); rm -rf /", "../../etc", ""] {
        do {
            _ = try await agent.listBackups(serviceID: hostile)
            report.check("ListBackups(\(hostile.isEmpty ? "empty" : hostile)) is refused", false, "it answered")
        } catch {
            report.check("ListBackups(\(hostile.isEmpty ? "empty" : hostile)) is refused",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(90))")
        }
    }
    do {
        _ = try await agent.listBackups(serviceID: absent)
        report.note("the wrapper on this host does have an arm for \(absent) — the no-arm path is not exercised")
    } catch {
        report.check("a service the wrapper has no arm for is refused, not answered with an empty list",
                     rpcCode(error) == "failed_precondition",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(120))")
    }
    for hostile in ["/etc/shadow", "\(list.directory)/../../etc/shadow", "/opt/backups/nowhere/x.tar.gz",
                    "\(list.directory)/incoming", list.directory] {
        do {
            _ = try await agent.deleteBackup(serviceID: target, path: hostile)
            report.check("DeleteBackup(\(hostile)) is refused", false, "it deleted something")
        } catch {
            report.check("DeleteBackup(\(hostile)) is refused",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(90))")
        }
    }

    let afterRefusals = try await agent.listBackups(serviceID: target)
    report.check("no refusal changed anything in the backup directory",
                 afterRefusals.archives.map(\.path) == list.archives.map(\.path),
                 "\(list.archives.count) → \(afterRefusals.archives.count) archives")
}

@available(macOS 15.0, *)
func checkBackupSeam(_ backups: AgentBackupOperations, service: ManagedService,
                     list: Gryonixnexusd_V1_BackupList,
                     estimate: Gryonixnexusd_V1_BackupEstimate, report: Report) async throws {
    let entries = try await backups.listBackups(of: service)
    report.check("AgentBackupOperations — the app's own seam — maps the listing",
                 entries.count == min(list.archives.count, BackupListParser.defaultLimit),
                 entries.map { "\($0.displayName) \($0.sizeText) \($0.dateText)" }.joined(separator: " | "))
    report.check("an entry's name is the absolute path the delete and restore paths take",
                 entries.allSatisfy { $0.name.hasPrefix("/") },
                 entries.map(\.name).joined(separator: " "))
    let mapped = try await backups.estimate(of: service)
    let driftTolerance: UInt64 = 200_000_000
    func closeEnough(_ mapped: UInt64?, _ direct: UInt64) -> Bool {
        guard let mapped else { return false }
        return mapped > direct ? mapped - direct <= driftTolerance : direct - mapped <= driftTolerance
    }
    report.check("the seam maps the estimate to bytes the sheet can warn from",
                 closeEnough(mapped?.dataBytes, UInt64(estimate.dataBytes))
                    && closeEnough(mapped?.freeBytes, UInt64(estimate.freeBytes)),
                 "data \(mapped?.dataBytes ?? 0) vs \(estimate.dataBytes) B · " +
                 "free \(mapped?.freeBytes ?? 0) vs \(estimate.freeBytes) B · " +
                 "fits on disk: \(mapped?.fitsOnDisk ?? false)")
}

@available(macOS 15.0, *)
func checkFailingBackup(_ agent: AgentClient, backups: AgentBackupOperations, failing: String,
                        report: Report) async {
    var failPhases: [String] = []
    var failCompleted: Gryonixnexusd_V1_BackupEvent?
    var failError: Error?
    do {
        for try await backupEvent in agent.runBackup(serviceID: failing, encryption: .disabled) {
            switch backupEvent.phase {
            case .started: failPhases.append("started")
            case .progress: failPhases.append("progress")
            case .completed: failPhases.append("completed"); failCompleted = backupEvent
            default: failPhases.append("?")
            }
        }
    } catch { failError = error }
    report.check("a run that fails part-way ends with an error trailer AFTER a COMPLETED event",
                 failError != nil && failPhases.last == "completed",
                 "\(failPhases.joined(separator: " → ")) · " +
                 "\(rpcCode(failError) ?? "?"): \(rpcMessage(failError).prefix(120))")
    report.check("the failure quotes the wrapper's own words, not a code",
                 !rpcMessage(failError).isEmpty && !rpcMessage(failError).contains("\u{1B}"),
                 rpcMessage(failError).prefix(120).description)
    report.check("COMPLETED still carries the backup directory as re-read after the failure",
                 failCompleted?.hasBackups ?? false,
                 "directory=\(failCompleted?.backups.directory ?? "none") · " +
                 "\(failCompleted?.backups.archives.count ?? -1) archives")

    if let failingService = ServiceRegistry.all.first(where: {
        AgentServiceMapping.agentID(for: $0.id) == failing
    }) {
        do {
            _ = try await backups.backup(failingService, encrypt: false, passphrase: nil,
                                         onChunk: { _ in })
            report.check("a failed run throws through the app's seam", false, "it returned")
        } catch let AgentControlError.backupFailed(underlying, listing) {
            report.check("a failed run throws WITH the backup directory attached, even when it is empty",
                         true,
                         "\(rpcMessage(underlying).prefix(90)) · \(listing.count) archives")
        } catch {
            report.check("a failed run throws WITH the backup directory attached, even when it is empty",
                         false, "threw \(error) instead — the state was discarded")
        }
    }
}

@available(macOS 15.0, *)
func checkRealBackup(_ agent: AgentClient, target: String, list: Gryonixnexusd_V1_BackupList,
                     env: [String: String], report: Report) async throws {
    let passphrase = env["AGENT_BACKUP_PASSPHRASE"]
    var phases: [String] = []
    var progressLines = 0
    var completed: Gryonixnexusd_V1_BackupEvent?
    var runError: Error?
    do {
        for try await backupEvent in agent.runBackup(serviceID: target,
                                                     encryption: passphrase == nil ? .disabled : .enabled,
                                                     passphrase: passphrase ?? "") {
            switch backupEvent.phase {
            case .started: phases.append("started(\(backupEvent.target))")
            case .progress: progressLines += 1
            case .completed: phases.append("completed"); completed = backupEvent
            default: phases.append("?")
            }
        }
    } catch { runError = error }
    report.check("RunBackup streams STARTED … COMPLETED and names the wrapper label",
                 runError == nil && phases.first == "started(\(target))" && phases.last == "completed",
                 "\(phases.joined(separator: " → ")) · \(progressLines) output lines · " +
                 "error=\(runError.map { rpcMessage($0) } ?? "none")")
    report.check("COMPLETED carries the backup directory as re-read AFTER the run",
                 (completed?.backups.archives.count ?? 0) > list.archives.count
                 || (completed?.hasArchive ?? false),
                 "before \(list.archives.count) → after \(completed?.backups.archives.count ?? -1) · " +
                 "archive=\(completed?.archive.path ?? "none") \(completed?.archive.sizeBytes ?? 0) B")

    if let announced = completed?.archive, !announced.path.isEmpty {
        let after = try await agent.listBackups(serviceID: target)
        report.check("the announced archive is in the listing, with the same size",
                     after.archives.contains { $0.path == announced.path && $0.sizeBytes == announced.sizeBytes },
                     "\(announced.path) \(announced.sizeBytes) B")
        if passphrase != nil {
            report.check("the encrypted run really produced an encrypted archive",
                         announced.path.hasSuffix(".gpg"), announced.path)
        }
        report.check("no scratch entry of the wrapper's own is listed as a backup",
                     !after.archives.contains { $0.name.hasPrefix(".") },
                     after.archives.map(\.name).joined(separator: " "))

        guard env["AGENT_BACKUP_KEEP"] != "1" else {
            report.note("AGENT_BACKUP_KEEP=1 — \(announced.path) is left on the host")
            return
        }
        let remaining = try await agent.deleteBackup(serviceID: target, path: announced.path)
        report.check("DeleteBackup answers with the listing as re-read after it",
                     !remaining.archives.contains { $0.path == announced.path },
                     "\(after.archives.count) → \(remaining.archives.count) archives")
    }
}

func drainUpdate(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_UpdateEvent, Error>)
    async -> ([Gryonixnexusd_V1_UpdateEvent], Error?) {
    var events: [Gryonixnexusd_V1_UpdateEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, error)
    }
    return (events, nil)
}

@available(macOS 15.0, *)
func updateSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment

    // ── CheckUpdates: every installed service gets an answer, never UNSPECIFIED ──
    let checked = try await agent.checkUpdates()
    report.check("CheckUpdates answers with at least one service row",
                 !checked.services.isEmpty,
                 checked.services.map { "\($0.serviceID):\($0.availability)" }.joined(separator: " "))
    report.check("no row comes back UNSPECIFIED — UNKNOWN is the honest 'could not answer'",
                 checked.services.allSatisfy { $0.availability != .unspecified },
                 checked.services.map { "\($0.serviceID):\($0.availability)" }.joined(separator: " "))
    report.check("UNKNOWN rows always carry a reason, AVAILABLE rows always name what moved",
                 checked.services.allSatisfy {
                     ($0.availability != .unknown || !$0.reason.isEmpty) &&
                     ($0.availability != .available || !$0.movedImages.isEmpty)
                 },
                 checked.services.map { "\($0.serviceID):\($0.availability):\($0.reason)" }.joined(separator: " "))

    // ── refusal on an unknown id, before anything opens ─────────────────────
    do {
        _ = try await agent.runUpdate(serviceID: "no-such-service").reduce(into: [Gryonixnexusd_V1_UpdateEvent]()) { $0.append($1) }
        report.check("RunUpdate(unknown id) is refused", false, "it answered instead")
    } catch {
        report.check("RunUpdate(unknown id) is refused", rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }

    // ── GetUpdatePolicy / SetUpdateSchedule round trip ───────────────────────
    let before = try await agent.getUpdatePolicy()
    report.note("policy before: schedule='\(before.schedule)' services=\(before.services) " +
                "last_run=\(before.lastRun.map { "\($0.serviceID):\($0.outcome)" })")

    let installedIDs = checked.services.map(\.serviceID).sorted()
    let probeSchedule = "every:1d@03:30"
    let set = try await agent.setUpdateSchedule(schedule: probeSchedule, services: installedIDs)
    report.check("SetUpdateSchedule echoes the schedule string verbatim",
                 set.schedule == probeSchedule, set.schedule)
    report.check("SetUpdateSchedule's service list is the RE-READ server state, a superset check " +
                 "since self-managed ids (none on this host) would be stripped",
                 Set(set.services) == Set(installedIDs),
                 "asked \(installedIDs) got \(set.services)")

    let reread = try await agent.getUpdatePolicy()
    report.check("GetUpdatePolicy after SetUpdateSchedule matches what SetUpdateSchedule just returned",
                 reread.schedule == set.schedule && Set(reread.services) == Set(set.services),
                 "schedule='\(reread.schedule)' services=\(reread.services)")

    let restored = try await agent.setUpdateSchedule(schedule: before.schedule, services: before.services)
    report.check("schedule restored to what it was before this section ran",
                 restored.schedule == before.schedule, restored.schedule)

    try await checkUpdateRun(agent, before: before, env: env, report: report)
}

@available(macOS 15.0, *)
func checkUpdateRun(_ agent: AgentClient, before: Gryonixnexusd_V1_UpdatePolicy, env: [String: String], report: Report) async throws {
    guard let target = env["AGENT_UPDATE_SERVICE"] else {
        report.note("AGENT_UPDATE_SERVICE unset — RunUpdate is not exercised")
        return
    }
    let (events, error) = await drainUpdate(agent.runUpdate(serviceID: target))
    report.check("RunUpdate(\(target)) streams STARTED … COMPLETED",
                 events.first?.phase == .started && events.last?.phase == .completed,
                 "\(events.map { "\($0.phase):\($0.outcome)" }) error=\(error.map { "\($0)" } ?? "none")")
    let outcome = events.last?.outcome
    report.check("a trailer error is present iff the outcome was not UPDATED",
                 (outcome == .updated) == (error == nil),
                 "outcome=\(outcome.map { "\($0)" } ?? "none") error=\(error.map { "\($0)" } ?? "none")")
    report.check("COMPLETED carries an outcome, never UNSPECIFIED",
                 outcome != .unspecified && outcome != nil,
                 "\(outcome.map { "\($0.rawValue)" } ?? "none")")
    report.check("COMPLETED carries a freshly re-read status for the service",
                 events.last?.hasStatus == true && !(events.last?.status.service.containers.isEmpty ?? true),
                 events.last?.status.service.containers.map { "\($0.name):\($0.state)" }.description ?? "none")
    if let outcome = events.last?.outcome {
        switch outcome {
        case .updated:
            report.note("\(target) updated cleanly — this is the real pull+recreate+health path, not a no-op")
        case .rolledBack:
            report.note("\(target) rolled back — reason: \(events.last?.reason ?? "")")
        case .failed:
            report.note("\(target) failed before any image was swapped — reason: \(events.last?.reason ?? "")")
        default:
            break
        }
    }
    report.note("progress lines seen: \(events.filter { $0.phase == .progress }.count)")
}

func drainUninstall(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_UninstallEvent, Error>)
    async -> ([Gryonixnexusd_V1_UninstallEvent], Error?) {
    var events: [Gryonixnexusd_V1_UninstallEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, error)
    }
    return (events, nil)
}

@available(macOS 15.0, *)
func removalSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let target = env["AGENT_REMOVE_SERVICE"] else {
        report.note("AGENT_REMOVE_SERVICE unset — RemoveService is not exercised")
        return
    }

    let before = try await agent.serviceStatus(serviceID: target)
    report.check("the target is actually installed before removal", before.installed,
                 "installed=\(before.installed)")

    // ── refusal on an unknown id, before anything opens ─────────────────────
    do {
        _ = try await agent.removeService(serviceID: "no-such-service", purgeData: false, purgeBackups: false)
            .reduce(into: [Gryonixnexusd_V1_UninstallEvent]()) { $0.append($1) }
        report.check("RemoveService(unknown id) is refused", false, "it answered instead")
    } catch {
        report.check("RemoveService(unknown id) is refused", rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }

    let purgeData = env["AGENT_REMOVE_PURGE_DATA"] == "1"
    if purgeData { report.note("AGENT_REMOVE_PURGE_DATA=1 — \(target)'s data goes with it") }
    let (events, error) = await drainUninstall(agent.removeService(serviceID: target, purgeData: purgeData, purgeBackups: false))
    report.check("RemoveService(\(target)) streams STARTED … COMPLETED with no trailer error",
                 error == nil && events.first?.phase == .started && events.last?.phase == .completed,
                 "\(events.map(\.phase)) error=\(error.map { "\($0)" } ?? "none")")
    report.check("COMPLETED reports the service as no longer installed",
                 events.last?.hasStatus == true && events.last?.status.installed == false,
                 "installed=\(events.last?.status.installed ?? true)")

    let after = try await agent.serviceStatus(serviceID: target)
    report.check("a fresh ServiceStatus call agrees: gone",
                 !after.installed && after.service.containers.isEmpty,
                 "installed=\(after.installed) containers=\(after.service.containers.map(\.name))")
}

func drainInstall(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_InstallServiceEvent, Error>)
    async -> ([Gryonixnexusd_V1_InstallServiceEvent], Error?) {
    var events: [Gryonixnexusd_V1_InstallServiceEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, error)
    }
    return (events, nil)
}

@available(macOS 15.0, *)
func drainPull(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_ModelPullEvent, Error>)
    async -> ([Gryonixnexusd_V1_ModelPullEvent], Error?) {
    var events: [Gryonixnexusd_V1_ModelPullEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, error)
    }
    return (events, nil)
}

func parseInstallSettings(_ raw: String?) -> [String: String] {
    guard let raw, !raw.isEmpty else { return [:] }
    var out: [String: String] = [:]
    for pair in raw.split(separator: ",") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        out[String(parts[0])] = String(parts[1])
    }
    return out
}

func lastProgressLines(_ events: [Gryonixnexusd_V1_InstallServiceEvent], _ count: Int = 10) -> String {
    events.filter { $0.phase == .progress }.suffix(count)
        .map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n    ")
}

@available(macOS 15.0, *)
func installSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let target = env["AGENT_INSTALL_SERVICE"] else {
        report.note("AGENT_INSTALL_SERVICE unset — the install section is not exercised")
        return
    }
    guard let domain = env["AGENT_INSTALL_DOMAIN"] else {
        report.note("AGENT_INSTALL_DOMAIN unset — the install section needs one and is skipped")
        return
    }
    let localOnly = env["AGENT_INSTALL_LOCAL_ONLY"] == "1"
    let adminUsername = env["AGENT_INSTALL_ADMIN"] ?? "admin"
    let settings = parseInstallSettings(env["AGENT_INSTALL_SETTING"])

    // ── refusal on an unknown id, before anything opens ──────────────────────
    do {
        _ = try await agent.installService(serviceID: "not-a-service", domain: domain)
            .reduce(into: [Gryonixnexusd_V1_InstallServiceEvent]()) { $0.append($1) }
        report.check("InstallService(unknown id) is refused before opening a stream", false, "it answered instead")
    } catch {
        report.check("InstallService(unknown id) is refused before opening a stream",
                     rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }

    if let absent = env["AGENT_INSTALL_ABSENT_ID"] {
        do {
            _ = try await agent.installService(serviceID: absent, domain: domain)
                .reduce(into: [Gryonixnexusd_V1_InstallServiceEvent]()) { $0.append($1) }
            report.check("InstallService(\(absent), no executor yet) is refused", false, "it answered instead")
        } catch {
            report.check("InstallService(\(absent), no executor yet) fails with failed_precondition, " +
                         "not not_found or invalid_argument",
                         rpcCode(error) == "failed_precondition",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
        }
    } else {
        report.note("AGENT_INSTALL_ABSENT_ID unset — the no-executor-yet refusal is not exercised")
    }

    try await checkRealInstall(agent, target: target, domain: domain, localOnly: localOnly, adminUsername: adminUsername, settings: settings, env: env, report: report)
}

@available(macOS 15.0, *)
func checkRealInstall(_ agent: AgentClient, target: String, domain: String, localOnly: Bool, adminUsername: String, settings: [String: String], env: [String: String], report: Report) async throws {
    // ── the real install ───────────────────────────────────────────────────
    let (events, error) = await drainInstall(agent.installService(
        serviceID: target, domain: domain, localOnly: localOnly,
        adminUsername: adminUsername, settings: settings))
    report.check("InstallService(\(target)) streams STARTED … COMPLETED with no trailer error",
                 error == nil && events.first?.phase == .started && events.last?.phase == .completed,
                 "\(events.map(\.phase)) error=\(error.map { "\($0)" } ?? "none")\n" +
                 "    last progress lines:\n    \(lastProgressLines(events))")
    report.check("STARTED names the compose project being touched",
                 !(events.first?.project.isEmpty ?? true),
                 events.first?.project ?? "none")
    let progress = events.filter { $0.phase == .progress }
    report.check("every PROGRESS event carries a recognized stream tag",
                 progress.allSatisfy { ["agent", "stdout", "stderr"].contains($0.stream) },
                 Set(progress.map(\.stream)).sorted().joined(separator: " "))
    report.check("COMPLETED carries the freshly re-read service, with the id we asked for",
                 events.last?.hasService == true && events.last?.service.id == target,
                 "id=\(events.last?.service.id ?? "none") status=\(events.last?.service.status ?? .unspecified)")

    // ── confirmation from OUTSIDE the stream just checked ────────────────────
    let status = try await agent.serviceStatus(serviceID: target)
    report.check("a fresh, independent ServiceStatus call agrees the service is installed",
                 status.installed, "installed=\(status.installed) status=\(status.service.status)")
    let discovered = try await agent.discover()
    report.check("a fresh Discover scan lists it too — not just something the install stream claimed",
                 discovered.services.contains { $0.id == target },
                 discovered.services.map(\.id).joined(separator: " "))

    // ── idempotency: a second run is a repair, not a refusal ─────────────────
    guard env["AGENT_INSTALL_TWICE"] == "1" else {
        report.note("AGENT_INSTALL_TWICE unset — re-running the same install is not exercised")
        return
    }
    let (secondEvents, secondError) = await drainInstall(agent.installService(
        serviceID: target, domain: domain, localOnly: localOnly,
        adminUsername: adminUsername, settings: settings))
    report.check("a second InstallService(\(target)) on the same host also reaches COMPLETED — " +
                 "idempotent by construction, not gated on an \"already installed\" flag",
                 secondError == nil && secondEvents.last?.phase == .completed,
                 "\(secondEvents.map(\.phase)) error=\(secondError.map { "\($0)" } ?? "none")\n" +
                 "    last progress lines:\n    \(lastProgressLines(secondEvents))")
}

// MARK: - An install that outlives the client that started it

@available(macOS 15.0, *)
func detachedInstallSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let target = env["AGENT_DETACH_SERVICE"] else {
        report.note("AGENT_DETACH_SERVICE unset — the detach/reattach path is not exercised")
        return
    }
    let domain = env["AGENT_INSTALL_DOMAIN"] ?? "example.com"
    let localOnly = env["AGENT_INSTALL_LOCAL_ONLY"] == "1"
    let adminUsername = env["AGENT_INSTALL_ADMIN"] ?? ""
    let settings = parseInstallSettings(env["AGENT_DETACH_SETTINGS"])

    func tail(_ events: [Gryonixnexusd_V1_InstallServiceEvent], _ count: Int = 10) -> String {
        events.filter { $0.phase == .progress }.suffix(count)
            .map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n    ")
    }

    // ── start it, learn its name, then WALK AWAY ────────────────────────────
    var jobID = ""
    var seen = 0
    let stream = agent.installService(serviceID: target, domain: domain, localOnly: localOnly,
                                      adminUsername: adminUsername, settings: settings)
    do {
        for try await event in stream {
            if jobID.isEmpty { jobID = event.jobID }
            seen += 1
            if seen >= 2 { break }
        }
    } catch {
        report.check("InstallService(\(target)) got far enough to name its run", false, "\(error)")
        return
    }
    report.check("the very first events carry a job id — the earliest a client could leave",
                 !jobID.isEmpty, "job=\(jobID.isEmpty ? "none" : jobID) after \(seen) events")
    guard !jobID.isEmpty else { return }

    let (_, secondError) = await drainInstall(agent.installService(
        serviceID: target, domain: domain, localOnly: localOnly,
        adminUsername: adminUsername, settings: settings))
    report.check("a second InstallService(\(target)) while the first is still going is refused, " +
                 "rather than racing it on the same compose project",
                 rpcCode(secondError ?? AgentError.transport("none")) == "already_exists",
                 "\(rpcCode(secondError ?? AgentError.transport("none")) ?? "?"): " +
                 "\(rpcMessage(secondError ?? AgentError.transport("none")))")

    let running = try await agent.listJobs()
    let listed = running.first { $0.jobID == jobID }
    report.check("ListJobs names the install this device started, and calls it RUNNING",
                 listed?.outcome == .running && listed?.kind == .install,
                 "outcome=\(listed?.outcome.rawValue.description ?? "not listed") " +
                 "kind=\(listed?.kind.rawValue.description ?? "?") " +
                 "subject=\(listed?.subject ?? "?")")

    // ── come back for it, from the first line ──────────────────────────────
    let (events, error) = await drainInstall(agent.watchInstall(jobID: jobID))
    report.check("WatchInstall replays the run from its first line and follows it to COMPLETED — " +
                 "the install finished with nobody watching",
                 error == nil && events.last?.phase == .completed,
                 "\(events.count) events, phases \(events.map(\.phase).prefix(3))… " +
                 "error=\(error.map { "\($0)" } ?? "none")\n" +
                 "    last progress lines:\n    \(tail(events))")
    report.check("the replay starts at the beginning, not where the dropped stream stopped",
                 events.first?.phase == .started,
                 "first=\(String(describing: events.first?.phase)) seq=\(events.first?.sequence ?? 0)")
    report.check("sequences arrive in order and without holes",
                 events.enumerated().allSatisfy { $0.element.sequence == UInt64($0.offset) },
                 events.map { String($0.sequence) }.prefix(8).joined(separator: " ") + "…")

    // ── and the finished run reads back as finished ────────────────────────
    let after = try await agent.listJobs()
    let done = after.first { $0.jobID == jobID }
    report.check("once it ends the same job reads back as SUCCEEDED, not RUNNING for ever",
                 done?.outcome == .succeeded,
                 "outcome=\(done?.outcome.rawValue.description ?? "not listed") " +
                 "finished=\(done?.finishedUnix ?? 0)")

    // ── confirmed from OUTSIDE anything this section streamed ──────────────
    let status = try await agent.serviceStatus(serviceID: target)
    report.check("an independent ServiceStatus agrees the service the app walked away from is installed",
                 status.installed, "installed=\(status.installed) status=\(status.service.status)")
}

// MARK: - The admin guard, seen from OUTSIDE the machine it guards

@available(macOS 15.0, *)
func lockdownSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let raw = env["AGENT_LOCKDOWN_URL"], let url = URL(string: raw) else {
        report.note("AGENT_LOCKDOWN_URL unset — the admin guard is not exercised from outside")
        return
    }

    /// The status a stranger gets
    func statusFromOutside() async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    let before = try await agent.getLockdown()
    report.note("guard before: mode=\(before.mode) hosts=\(before.hosts)")
    let open = await statusFromOutside()
    report.check("with the guard off the page answers the open internet",
                 open == 200, "HTTP \(open.map(String.init) ?? "no answer")")

    // ── on ──────────────────────────────────────────────────────────────────
    let on = try await agent.setLockdown(mode: .all)
    report.check("SetLockdown answers with the state the WRAPPER reports, not the request echoed back",
                 on.mode == .all, "\(on.mode)")
    var guarded: Int?
    for _ in 0..<10 {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guarded = await statusFromOutside()
        if guarded != 200 { break }
    }
    report.check("with the guard on the same page stops answering from outside — " +
                 "the claim the switch makes, checked where it is made",
                 guarded == 403,
                 "HTTP \(guarded.map(String.init) ?? "no answer")")

    if let publicRaw = env["AGENT_LOCKDOWN_PUBLIC_URL"], let publicURL = URL(string: publicRaw) {
        var request = URLRequest(url: publicURL)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let status = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        report.check("a public path stays reachable with the guard on — the webhook a stranger's " +
                     "server calls is not the page a stranger's browser opens",
                     status != nil && status != 403,
                     "HTTP \(status.map(String.init) ?? "no answer")")
    } else {
        report.note("AGENT_LOCKDOWN_PUBLIC_URL unset — the public-path exemption is not exercised")
    }

    let restored = try await agent.setLockdown(mode: before.mode == .unspecified ? .off : before.mode,
                                               hosts: before.hosts)
    report.check("the guard is put back the way this section found it",
                 restored.mode == before.mode || (before.mode == .unspecified && restored.mode == .off),
                 "\(before.mode) → \(restored.mode)")
    var reopened: Int?
    for _ in 0..<10 {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        reopened = await statusFromOutside()
        if reopened == 200 { break }
    }
    report.check("and the page answers again", reopened == 200,
                 "HTTP \(reopened.map(String.init) ?? "no answer")")
}

@available(macOS 15.0, *)
func restoreSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let target = env["AGENT_RESTORE_SERVICE"] else {
        report.note("AGENT_RESTORE_SERVICE unset — RunRestore is not exercised")
        return
    }
    let passphrase = env["AGENT_RESTORE_PASSPHRASE"] ?? ""

    let list = try await agent.listBackups(serviceID: target)
    guard let archive = env["AGENT_RESTORE_ARCHIVE"] ?? list.archives.first?.path else {
        report.check("there is an archive to restore from", false, "\(list.directory) is empty")
        return
    }
    report.note("restoring \(target) from \(archive)")

    // ── refusals, before anything touches the live data ─────────────────────
    do {
        _ = try await agent.runRestore(serviceID: "no-such-service", archivePath: archive)
            .reduce(into: [Gryonixnexusd_V1_RestoreEvent]()) { $0.append($1) }
        report.check("RunRestore(unknown service) is refused", false, "it answered instead")
    } catch {
        report.check("RunRestore(unknown service) is refused", rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }
    for hostile in ["/etc/shadow", "\(list.directory)/../../etc/passwd", ""] {
        do {
            _ = try await agent.runRestore(serviceID: target, archivePath: hostile)
                .reduce(into: [Gryonixnexusd_V1_RestoreEvent]()) { $0.append($1) }
            report.check("RunRestore refuses an archive outside the backup directory (\(hostile))",
                         false, "it answered instead")
        } catch {
            report.check("RunRestore refuses an archive outside the backup directory (\(hostile))",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
        }
    }

    // ── the run itself ──────────────────────────────────────────────────────
    var events: [Gryonixnexusd_V1_RestoreEvent] = []
    var runError: Error?
    do {
        for try await event in agent.runRestore(serviceID: target, archivePath: archive,
                                                passphrase: passphrase) {
            events.append(event)
        }
    } catch {
        runError = error
    }

    func tail(_ count: Int = 8) -> String {
        events.filter { $0.phase == .progress }.suffix(count)
            .map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n    ")
    }
    report.check("RunRestore(\(target)) streams STARTED … COMPLETED with no trailer error",
                 runError == nil && events.first?.phase == .started && events.last?.phase == .completed,
                 "\(events.count) events error=\(runError.map { rpcMessage($0) } ?? "none")\n    " + tail())
    report.check("every event names the run on the host, so a client that left can come back",
                 events.allSatisfy { !$0.jobID.isEmpty },
                 "job=\(events.first?.jobID ?? "none")")
    report.check("COMPLETED carries the status as RE-READ after the restore, not the request echoed back",
                 events.last?.hasStatus == true && events.last?.status.installed == true,
                 "installed=\(events.last?.status.installed ?? false) " +
                 "status=\(String(describing: events.last?.status.service.status))")

    let after = try await agent.serviceStatus(serviceID: target)
    report.check("an independent ServiceStatus agrees the service is up again after the restore",
                 after.installed && !after.service.containers.isEmpty,
                 "installed=\(after.installed) containers=\(after.service.containers.map(\.name))")
}

// MARK: - A provider key saved from a device

@available(macOS 15.0, *)
func providerKeySection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let gateway = env["AGENT_LLM_GATEWAY_URL"], let master = env["AGENT_LLM_MASTER_KEY"] else {
        report.note("AGENT_LLM_GATEWAY_URL / AGENT_LLM_MASTER_KEY unset — the provider-key path is not exercised")
        return
    }
    let provider = env["AGENT_LLM_PROVIDER"] ?? "openai"
    let model = env["AGENT_LLM_MODEL"] ?? "openai/gpt-4o-mini"

    func askGateway() async -> String {
        guard let url = URL(string: "\(gateway)/v1/chat/completions") else { return "bad url" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(master)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
            {"model":"\(model)","messages":[{"role":"user","content":"ping"}],"max_tokens":1}
            """.utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "transport: \(error)"
        }
    }

    let before = await askGateway()
    report.check("with no key saved, the gateway refuses that provider because the variable is unset",
                 before.contains("OPENAI_API_KEY") || before.lowercased().contains("api_key"),
                 String(before.prefix(160)))

    let id = "single|LiteLLM \(provider)"
    var entry = Gryonixnexusd_V1_VaultEntry()
    entry.id = id
    entry.host = "single"
    entry.title = "LiteLLM \(provider)"
    entry.serviceSecret = "litellm/\(provider)"
    entry.token = "sk-smoke-not-a-real-key-0000000000000000"
    entry.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    entry.updatedBy = "agent-smoke"

    let saved = try await agent.putVaultEntries([entry])
    report.check("PutVaultEntries answers with the snapshot holding the row the device just saved",
                 saved.entries.contains { $0.id == id && $0.serviceSecret == "litellm/\(provider)" },
                 "\(saved.entries.count) entries")

    var after = ""
    for _ in 0..<24 {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        after = await askGateway()
        if !after.isEmpty && !after.contains("must be set") { break }
    }
    report.check("once the key is saved the gateway reaches the provider and is refused THERE — " +
                 "the file was rendered and the container restarted, with no verb of its own",
                 !after.contains("must be set") &&
                 (after.lowercased().contains("incorrect api key") ||
                  after.lowercased().contains("invalid_api_key") ||
                  after.lowercased().contains("authenticationerror")),
                 String(after.prefix(200)))

    _ = try await agent.deleteVaultEntry(id: id, deviceUID: "agent-smoke")
    var restored = ""
    for _ in 0..<24 {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        restored = await askGateway()
        if restored.contains("must be set") { break }
    }
    report.check("deleting the row takes the key off the host again",
                 restored.contains("must be set") || restored.lowercased().contains("api_key"),
                 String(restored.prefix(160)))
}

// MARK: - The models the engine runs

@available(macOS 15.0, *)
func modelsSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment

    let before = try await agent.listModels()
    guard before.enginePresent else {
        report.check("a host with no engine says so rather than answering an empty list",
                     !before.enginePresent && before.models.isEmpty,
                     "engine=\(before.enginePresent) models=\(before.models.count)")
        if env["AGENT_MODEL_PULL"] != nil {
            report.check("AGENT_MODEL_PULL was asked for on a host with no engine", false,
                         "install the engine first")
        } else {
            report.note("no engine on this host — the rest of the models section does not apply")
        }
        return
    }
    report.check("the listing carries the free space a pull is refused against, not just the models",
                 before.diskFreeBytes > 0 && before.diskTotalBytes >= before.diskFreeBytes,
                 "\(before.diskFreeBytes) free of \(before.diskTotalBytes) at \(before.path)")
    report.note("models before: [\(before.models.map(\.name).joined(separator: ", "))]")

    if let tooBig = env["AGENT_MODEL_TOO_BIG"] {
        let (events, error) = await drainPull(agent.pullModel(name: tooBig))
        let refused = error != nil && events.last?.phase != .completed
        report.check("a model that does not fit is refused rather than started",
                     refused,
                     "\(events.count) events, last=\(String(describing: events.last?.phase)) " +
                     "error=\(error.map { rpcMessage($0) } ?? "none")")
    } else {
        report.note("AGENT_MODEL_TOO_BIG unset — the free-space refusal is not exercised")
    }

    guard let name = env["AGENT_MODEL_PULL"] else {
        report.note("AGENT_MODEL_PULL unset — no model is fetched")
        return
    }

    try await checkModelPull(agent, name: name, before: before, env: env, report: report)
}

@available(macOS 15.0, *)
func checkModelPull(_ agent: AgentClient, name: String, before: Gryonixnexusd_V1_ModelList, env: [String: String], report: Report) async throws {
    // ── start the pull, take its name, and WALK AWAY ────────────────────────
    var jobID = ""
    var sawTotal = false
    var seen = 0
    do {
        for try await event in agent.pullModel(name: name) {
            if jobID.isEmpty { jobID = event.jobID }
            if event.totalBytes > 0 { sawTotal = true }
            seen += 1
            if !jobID.isEmpty && (sawTotal || seen >= 6) { break }
        }
    } catch {
        report.check("PullModel(\(name)) got far enough to name its run", false, "\(error)")
        return
    }
    report.check("every event carries the job id — the earliest point a client could leave",
                 !jobID.isEmpty, "job=\(jobID.isEmpty ? "none" : jobID) after \(seen) events")
    guard !jobID.isEmpty else { return }
    report.check("the size is learned from the engine's own progress rather than guessed before the pull",
                 sawTotal || seen >= 6,
                 sawTotal ? "a total arrived" : "no total in the first \(seen) events")

    // ── the host still knows about it with nobody attached ─────────────────
    let running = try await agent.listJobs(runningOnly: true)
    let listed = running.first { $0.jobID == jobID }
    report.check("ListJobs names the pull this device started, as its own kind and RUNNING",
                 listed?.outcome == .running && listed?.kind == .modelPull,
                 "outcome=\(listed?.outcome.rawValue.description ?? "not listed") " +
                 "kind=\(listed?.kind.rawValue.description ?? "?") " +
                 "subject=\(listed?.subject ?? "?")")

    // ── come back for it ───────────────────────────────────────────────────
    var jobEvents: [Gryonixnexusd_V1_JobEvent] = []
    var watchError: Error?
    do {
        for try await event in agent.watchJob(jobID: jobID) { jobEvents.append(event) }
    } catch { watchError = error }
    report.check("WatchJob replays the pull from its first line and follows it to the end — " +
                 "the fetch ran on with nobody watching",
                 watchError == nil && jobEvents.last?.phase == .completed,
                 "\(jobEvents.count) events, last=\(String(describing: jobEvents.last?.phase)) " +
                 "error=\(watchError.map { "\($0)" } ?? "none")")
    report.check("the replay starts at the beginning, not where the dropped stream stopped",
                 jobEvents.first?.sequence == 0,
                 "first seq=\(jobEvents.first?.sequence ?? 0)")

    // ── and the engine actually has it now ─────────────────────────────────
    let after = try await agent.listModels()
    report.check("the model the app walked away from is on the engine when it comes back",
                 after.models.contains { $0.name == name },
                 "[\(after.models.map(\.name).joined(separator: ", "))]")
    report.check("it weighs something, and the free space moved down by roughly that much",
                 after.models.first { $0.name == name }.map { $0.sizeBytes > 0 } ?? false,
                 "size=\(after.models.first { $0.name == name }?.sizeBytes ?? 0) " +
                 "free \(before.diskFreeBytes) → \(after.diskFreeBytes)")

    if env["AGENT_MODEL_KEEP"] == "1" {
        report.note("AGENT_MODEL_KEEP=1 — \(name) is left on the host")
        return
    }
    // ── and it goes away again, answering with the re-read listing ─────────
    let deleted = try await agent.deleteModel(name: name)
    report.check("DeleteModel answers with the RE-READ listing, without the model in it",
                 !deleted.models.contains { $0.name == name },
                 "[\(deleted.models.map(\.name).joined(separator: ", "))]")
    let confirm = try await agent.listModels()
    report.check("a fresh ListModels agrees it is gone",
                 !confirm.models.contains { $0.name == name },
                 "[\(confirm.models.map(\.name).joined(separator: ", "))]")
}

@available(macOS 15.0, *)
func wrapperlessSection(_ client: SSHClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let bridge = env["AGENT_BACKUP_WRAPPERLESS_BRIDGE"] else {
        report.note("AGENT_BACKUP_WRAPPERLESS_BRIDGE unset — the no-wrapper path is not exercised")
        return
    }
    let target = env["AGENT_BACKUP_SERVICE"] ?? "docker-mailserver"
    let agent = AgentClient(transport: SSHAgentTransport(client: client, bridgeCommand: bridge))

    for (name, call) in [
        ("ListBackups", { try await agent.listBackups(serviceID: target) as Any }),
        ("EstimateBackup", { try await agent.estimateBackup(serviceID: target) as Any })
    ] as [(String, @Sendable () async throws -> Any)] {
        do {
            _ = try await call()
            report.check("\(name) on a host with no backup wrapper is refused", false, "it answered")
        } catch {
            report.check("\(name) on a host with no backup wrapper is refused, with what to do about it",
                         rpcCode(error) == "failed_precondition" && rpcMessage(error).contains("setup"),
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(140))")
        }
    }
    let (events, error) = await drainBackup(agent.runBackup(serviceID: target))
    report.check("RunBackup on a host with no backup wrapper refuses BEFORE acting, with no events",
                 events.isEmpty && rpcCode(error) == "failed_precondition",
                 "events=\(events.count) · \(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(140))")
}

@available(macOS 15.0, *)
func drainBackup(_ stream: AsyncThrowingStream<Gryonixnexusd_V1_BackupEvent, Error>)
    async -> ([Gryonixnexusd_V1_BackupEvent], Error?) {
    var events: [Gryonixnexusd_V1_BackupEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, error)
    }
    return (events, nil)
}

@available(macOS 15.0, *)
func mailboxSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let domain = env["AGENT_MAILBOX_DOMAIN"] else {
        report.note("AGENT_MAILBOX_DOMAIN unset — the mailbox section is not exercised")
        return
    }
    let stamp = Int(Date().timeIntervalSince1970) % 100_000
    let address = "gd-smoke-\(stamp)@\(domain)"
    let password = env["AGENT_MAILBOX_PASSWORD"] ?? "Sm0ke-\(stamp)-pass"

    let before = try await agent.listMailboxes()
    report.check("ListMailboxes answers on a live engine", true,
                 "\(before.count) mailboxes: \(before.map(\.address))")

    // ── refusals BEFORE the engine is touched ───────────────────────────────
    for bad in ["-admin@\(domain)", "a@b@c", "admin@\(domain); rm -rf /", "admin", "@\(domain)"] {
        do {
            _ = try await agent.createMailbox(address: bad, password: password)
            report.check("CreateMailbox(\(bad)) is refused", false, "it was accepted")
        } catch {
            report.check("CreateMailbox(\(bad)) is refused before the engine is touched",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(80))")
        }
    }
    do {
        _ = try await agent.createMailbox(address: address, password: "")
        report.check("an empty password is refused", false, "it was accepted")
    } catch {
        report.check("an empty password is refused", rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error))")
    }
    // Nothing above may have changed the server.
    let unchanged = try await agent.listMailboxes()
    report.check("no refusal changed anything on the server",
                 unchanged.map(\.address) == before.map(\.address), "\(unchanged.count) mailboxes")

    try await checkMailboxLifecycle(agent, domain: domain, stamp: stamp, address: address, password: password, before: before, env: env, report: report)
}

@available(macOS 15.0, *)
func checkMailboxLifecycle(_ agent: AgentClient, domain: String, stamp: Int, address: String, password: String, before: [Gryonixnexusd_V1_Mailbox], env: [String: String], report: Report) async throws {
    // ── create ──────────────────────────────────────────────────────────────
    let afterCreate = try await agent.createMailbox(address: address, password: password)
    report.check("CreateMailbox answers with the listing as re-read AFTER the change",
                 afterCreate.contains { $0.address == address },
                 "\(afterCreate.count) mailboxes, new one present: \(afterCreate.contains { $0.address == address })")
    if let created = afterCreate.first(where: { $0.address == address }) {
        report.check("a just-created mailbox parses with its empty brackets",
                     created.manageable, "detail=\(created.detail.debugDescription)")
    }

    if env["AGENT_MAILBOX_PASSWORD"] != nil {
        _ = try await agent.setMailboxPassword(address: address, password: password)
        report.note("password calls done with the marked password — read the /proc watcher's tally")
    }

    let raceAddress = "gd-race-\(stamp)@\(domain)"
    _ = try await agent.createMailbox(address: raceAddress, password: password)
    let deleteStart = Date()
    let afterDelete = try await agent.deleteMailbox(address: raceAddress)
    report.check("deleting a mailbox created seconds ago succeeds (the engine's race is waited out)",
                 !afterDelete.contains { $0.address == raceAddress },
                 String(format: "took %.1fs", Date().timeIntervalSince(deleteStart)))

    do {
        _ = try await agent.deleteMailbox(address: "gd-nobody-\(stamp)@\(domain)")
        report.check("deleting an address that does not exist fails", false, "it reported success")
    } catch {
        report.check("deleting an address that does not exist fails, quoting the engine",
                     rpcCode(error) == "failed_precondition" && !rpcMessage(error).isEmpty,
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(120))")
        report.check("the engine's error carries no ANSI escapes",
                     !rpcMessage(error).contains("\u{1B}"),
                     rpcMessage(error).prefix(80).description)
    }

    // ── the app's own layer, not just the wire ──────────────────────────────
    let ops = AgentMailboxOperations(client: agent, engineInstalled: true, gate: AgentChannelGate())
    let listed = try await ops.list()
    report.check("AgentMailboxOperations — the app's own seam — lists the same mailboxes",
                 listed.contains { $0.address == address },
                 "\(listed.count) rows: \(listed.map { "\($0.address)\($0.detail.map { " \($0)" } ?? "")" })")
    try await ops.setPassword(address: address, password: password)
    report.check("setPassword through the app's seam succeeds", true, "password changed")

    // ── clean up after ourselves ────────────────────────────────────────────
    try await ops.delete(address: address)
    let final = try await ops.list()
    report.check("the smoke mailboxes are gone again",
                 !final.contains { $0.address == address } && !final.contains { $0.address == raceAddress },
                 "\(final.count) mailboxes left: \(final.map(\.address))")
    report.check("the listing is back to what it was before the run",
                 Set(final.map(\.address)) == Set(before.map(\.address)),
                 "\(before.map(\.address)) vs \(final.map(\.address))")
}

/// The four VPN client verbs against a real panel
@available(macOS 15.0, *)
func vpnClientSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let raw = env["AGENT_VPN_PROTOCOL"] else {
        report.note("AGENT_VPN_PROTOCOL unset — the VPN client section is not exercised")
        return
    }
    let target = ServiceID(rawValue: raw)
    guard VPNClientProtocols.all.contains(target) else {
        report.check("AGENT_VPN_PROTOCOL names one of the five VPN protocols", false,
                     "'\(raw)' is not one of \(VPNClientProtocols.all.map(\.rawValue))")
        return
    }
    let ops = AgentVPNClientOperations(client: agent, gate: AgentChannelGate())

    let before = try await ops.list(protocol: target)
    report.check("ListVpnClients answers on a live panel", true,
                 "\(before.count) devices: \(before.map(\.name))")

    // ── refusals BEFORE anything is created ─────────────────────────────────
    do {
        _ = try await agent.listVPNClients(protocol: "not-a-protocol")
        report.check("an unknown protocol is refused", false, "it was accepted")
    } catch {
        report.check("an unknown protocol is refused as a client bug",
                     rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(80))")
    }
    if let absent = env["AGENT_VPN_ABSENT_PROTOCOL"] {
        do {
            _ = try await agent.listVPNClients(protocol: absent)
            report.check("a protocol this host does not run is refused", false, "it was accepted")
        } catch {
            report.check("a protocol this host does not run is refused as a precondition",
                         rpcCode(error) == "failed_precondition",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(90))")
        }
        do {
            _ = try await agent.addVPNClient(protocol: absent, clientName: "gd-smoke-should-not-exist")
            report.check("adding to a protocol this host does not run is refused", false, "it was accepted")
        } catch {
            report.check("adding to a protocol this host does not run is refused",
                         rpcCode(error) == "failed_precondition",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(90))")
        }
    } else {
        report.note("AGENT_VPN_ABSENT_PROTOCOL unset — the services.json gate is not exercised")
    }
    let unchanged = try await ops.list(protocol: target)
    report.check("no refusal changed anything on the server",
                 unchanged.map(\.id) == before.map(\.id), "\(unchanged.count) devices")

    try await checkVPNClientLifecycle(ops, target: target, before: before, report: report)
}

@available(macOS 15.0, *)
func checkVPNClientLifecycle(_ ops: AgentVPNClientOperations, target: ServiceID, before: [VPNClientDevice], report: Report) async throws {
    // ── add ─────────────────────────────────────────────────────────────────
    let name = "gd-smoke-\(Int(Date().timeIntervalSince1970) % 100_000)"
    let afterAdd = try await ops.add(protocol: target, named: name)
    let created = afterAdd.filter { device in !before.contains { $0.id == device.id } }
    report.check("AddVpnClient answers with the listing as re-read AFTER the change",
                 created.count == 1, "\(created.count) new device(s): \(created.map(\.name))")
    guard let device = created.first else { return }
    report.check("the new device carries an id and a name",
                 !device.id.isEmpty && !device.name.isEmpty, "\(device.id) / \(device.name)")

    let relisted = try await ops.list(protocol: target)
    report.check("a fresh list still shows it", relisted.contains { $0.id == device.id },
                 "\(relisted.count) devices")

    // ── configuration ───────────────────────────────────────────────────────
    let config = try await ops.configuration(protocol: target, clientID: device.id)
    report.check("GetVpnClientConfig returns something importable", config.text.count > 30,
                 "\(config.text.count) bytes")
    report.check("it names the file the protocol's own app expects",
                 !config.fileName.isEmpty, config.fileName)
    report.note("qrIsUseful=\(config.qrIsUseful) for \(target.rawValue) (\(config.fileName))")
    do {
        _ = try await ops.configuration(protocol: target, clientID: "no-such-client")
        report.check("an unknown client id is refused", false, "it was accepted")
    } catch {
        report.check("an unknown client id is refused", true,
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(80))")
    }

    // ── remove ──────────────────────────────────────────────────────────────
    let afterRemove = try await ops.remove(protocol: target, clientID: device.id)
    report.check("DeleteVpnClient's own answer no longer lists it",
                 !afterRemove.contains { $0.id == device.id }, "\(afterRemove.count) devices")
    let final = try await ops.list(protocol: target)
    report.check("a fresh list no longer shows it", !final.contains { $0.id == device.id },
                 "\(final.count) devices")
    report.check("the host is back to exactly the devices it started with",
                 final.map(\.id).sorted() == before.map(\.id).sorted(),
                 "\(final.count) vs \(before.count)")
}

/// The five mesh verbs against a real Headscale
@available(macOS 15.0, *)
func meshSection(_ agent: AgentClient, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["AGENT_MESH"] != nil else {
        report.note("AGENT_MESH unset — the mesh section is not exercised")
        return
    }
    let ops = AgentMeshOperations(client: agent, gate: AgentChannelGate())

    let before = try await ops.users()
    report.check("ListMeshUsers answers on a live control server", true,
                 "\(before.count) user(s): \(before.map(\.name))")

    for bad in ["", "  ", "has space", "semi;colon", "--reusable"] {
        let label = bad.trimmingCharacters(in: .whitespaces).isEmpty ? "empty" : bad
        do {
            _ = try await ops.createUser(named: bad)
            report.check("CreateMeshUser(\(label)) is refused", false, "it was accepted")
        } catch {
            report.check("CreateMeshUser(\(label)) is refused before the engine is touched",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(70))")
        }
    }
    let unchanged = try await ops.users()
    report.check("no refusal changed anything on the server",
                 unchanged.map(\.id) == before.map(\.id), "\(unchanged.count) user(s)")

    let name = "smoke\(Int(Date().timeIntervalSince1970) % 100_000)"
    let afterCreate = try await ops.createUser(named: name)
    let created = afterCreate.filter { user in !before.contains { $0.id == user.id } }
    report.check("CreateMeshUser answers with the listing as re-read AFTER the change",
                 created.count == 1, "\(created.count) new user(s): \(created.map(\.name))")
    guard let user = created.first else { return }

    let key = try await ops.mintAuthKey(userID: user.id, reusable: true, expirationHours: 1)
    report.check("CreateMeshAuthKey returns a usable key", key.key.hasPrefix("hskey-"),
                 String(key.key.prefix(12)) + "…")
    report.check("the key carries the terms it was asked for", key.isReusable, "reusable=\(key.isReusable)")
    report.check("it expires rather than living for ever", key.expiresAt != nil,
                 key.expiresAt.map { "\($0)" } ?? "no expiry")

    try await checkMeshNodes(ops, name: name, key: key, report: report)
}

@available(macOS 15.0, *)
func checkMeshNodes(_ ops: AgentMeshOperations, name: String, key: MeshAuthKey, report: Report) async throws {
    let nodes = try await ops.nodes()
    report.check("ListMeshNodes answers", true, "\(nodes.count) node(s): \(nodes.map(\.name))")
    report.check("no node's record carries a join key",
                 !nodes.contains { node in
                     node.name.contains("hskey-") || node.addresses.contains { $0.contains("hskey-") }
                 },
                 "checked \(nodes.count) node(s)")

    do {
        _ = try await ops.removeNode(id: "no-such-node")
        report.check("an unknown node id is refused", false, "it was accepted")
    } catch {
        report.check("an unknown node id is refused", rpcCode(error) != nil,
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(70))")
    }
    do {
        _ = try await ops.removeNode(id: "--force")
        report.check("a node id that is really a flag is refused", false, "it was accepted")
    } catch {
        report.check("a node id that is really a flag is refused as a client bug",
                     rpcCode(error) == "invalid_argument",
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(70))")
    }

    for bad in ["", "https://vault.example.com/admin", "has space", "-leading"] {
        let label = bad.isEmpty ? "empty" : bad
        do {
            _ = try await ops.publishNames([bad])
            report.check("PublishMeshNames(\(label)) is refused", false, "it was accepted")
        } catch {
            report.check("PublishMeshNames(\(label)) is refused as a client bug",
                         rpcCode(error) == "invalid_argument",
                         "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(70))")
        }
    }
    let published = try await ops.publishNames(["vault.smoke.invalid", "cloud.smoke.invalid"])
    report.check("PublishMeshNames answers with what it wrote", published.count == 2,
                 published.map { "\($0.name)→\($0.address)" }.joined(separator: " "))
    report.check("every published name points at one mesh address",
                 Set(published.map(\.address)).count == 1
                     && published.allSatisfy { $0.address.contains(".") },
                 Set(published.map(\.address)).joined(separator: ","))
    let cleared = try await ops.publishNames([])
    report.check("publishing nothing clears the names", cleared.isEmpty, "\(cleared.count) record(s)")
}

@available(macOS 15.0, *)
func brokenEngineSection(_ client: SSHClient, bridge: String, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let brokenBridge = env["AGENT_BROKEN_ENGINE_BRIDGE"] else {
        report.note("AGENT_BROKEN_ENGINE_BRIDGE unset — the unreachable-engine path is not exercised")
        return
    }
    let installed = env["AGENT_INSTALLED"] ?? "vaultwarden"
    let agent = AgentClient(transport: SSHAgentTransport(client: client, bridgeCommand: brokenBridge))

    do {
        _ = try await agent.serviceStatus(serviceID: installed)
        report.check("ServiceStatus with the engine unreachable fails", false, "it answered instead")
    } catch {
        report.check("ServiceStatus with the engine unreachable fails, quoting the engine",
                     rpcCode(error) == "unavailable" && rpcMessage(error).contains("Cannot connect to the Docker daemon"),
                     "\(rpcCode(error) ?? "?"): \(rpcMessage(error).prefix(120))")
    }

    let (events, error) = await drain(agent.controlService(serviceID: installed, action: .restart))
    report.check("ControlService with the engine unreachable fails before acting, with no events",
                 events.isEmpty && rpcCode(error) == "unavailable",
                 "events=\(events.count) \(rpcCode(error) ?? "none"): \(rpcMessage(error).prefix(120))")
}

extension AsyncThrowingStream where Failure == Error {
    func ignoringErrors() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                do { for try await element in self { continuation.yield(element) } } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Collects the progress callback's lines
final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return lines.count }
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined() }
}

// MARK: - The gate (AgentChannelGate) against real sshd MaxSessions

@available(macOS 15.0, *)
func gateSection(_ client: SSHClient, bridge: String, report: Report) async throws {
    let env = ProcessInfo.processInfo.environment
    let installed = env["AGENT_INSTALLED"] ?? "vaultwarden"
    guard let service = ServiceRegistry.all.first(where: { AgentCommandRunner.agentID(for: $0) == installed })
            ?? ServiceRegistry.service(.vaultwarden) else {
        report.note("no catalog service maps to \(installed) — gate section skipped")
        return
    }
    let agent = AgentClient(transport: SSHAgentTransport(client: client, bridgeCommand: bridge))

    let runner = AgentCommandRunner(client: agent, gate: AgentChannelGate())
    let progress = Progress()
    let rows = try await runner.power(.restart, on: service, onProgress: { progress.append($0) })
    report.check("AgentCommandRunner.power(.restart) — the app's own path — returns post-action rows",
                 !rows.isEmpty && rows.allSatisfy { $0.status.hasPrefix("Up") },
                 "rows=\(rows.map { "\($0.name):\($0.status)" }) progressLines=\(progress.count)")
    report.check("progress reached the caller line by line", progress.count > 0,
                 progress.text.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(120).description)

    if let failingID = env["AGENT_FAILING"],
       let failing = ServiceRegistry.all.first(where: { AgentCommandRunner.agentID(for: $0) == failingID }) {
        do {
            _ = try await runner.power(.start, on: failing)
            report.check("a failed run does not report success through the app's path", false, "it returned")
        } catch let AgentControlError.operationFailed(underlying, status) {
            report.check("a failed run throws WITH the post-action status attached",
                         !status.isEmpty,
                         "\(underlying) · status=\(status.map { "\($0.name):\($0.status)" })")
        } catch {
            report.check("a failed run throws WITH the post-action status attached", false,
                         "threw \(error) instead — the status was discarded")
        }
    }

    try await checkGateBurst(agent, client: client, installed: installed, service: service, report: report)
}

@available(macOS 15.0, *)
func checkGateBurst(_ agent: AgentClient, client: SSHClient, installed: String, service: any ManagedService, report: Report) async throws {
    let burst = 16

    let ungated = AgentCommandRunner(client: agent, gate: nil)
    let ungatedFailures = await withTaskGroup(of: String?.self) { group in
        for _ in 0 ..< burst {
            group.addTask { @Sendable in
                do { _ = try await ungated.status(of: service); return nil } catch { return "\(error)" }
            }
        }
        var failures: [String] = []
        for await failure in group { if let failure { failures.append(failure) } }
        return failures
    }
    report.observe("\(burst) UNGATED concurrent RPCs",
                   ungatedFailures.isEmpty
                   ? "all succeeded (this sshd tolerated \(burst) sessions)"
                   : "\(ungatedFailures.count)/\(burst) failed — e.g. \(ungatedFailures[0].prefix(120))")

    let streams = Task {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @Sendable in
                for await _ in agent.hostMetrics(intervalSeconds: 1).ignoringErrors() where !Task.isCancelled {}
            }
            group.addTask { @Sendable in
                for await _ in agent.logs(serviceID: installed, tail: 1).ignoringErrors() where !Task.isCancelled {}
            }
        }
    }
    try await Task.sleep(nanoseconds: 2_000_000_000)

    let gate = AgentChannelGate()
    let gated = AgentCommandRunner(client: agent, gate: gate)
    let gatedFailures = await withTaskGroup(of: String?.self) { group in
        for _ in 0 ..< burst {
            group.addTask { @Sendable in
                do { _ = try await gated.status(of: service); return nil } catch { return "\(error)" }
            }
        }
        var failures: [String] = []
        for await failure in group { if let failure { failures.append(failure) } }
        return failures
    }
    streams.cancel()
    report.check("\(burst) concurrent RPCs through AgentChannelGate all succeed, " +
                 "with two long streams holding channels beside it",
                 gatedFailures.isEmpty,
                 gatedFailures.isEmpty ? "0 failures" : "\(gatedFailures.count) failed — \(gatedFailures[0].prefix(160))")
}

// MARK: - Entry point

@available(macOS 15.0, *)
func run() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let host = env["AGENT_HOST"], let user = env["AGENT_USER"], let keyPath = env["AGENT_KEY"] else {
        FileHandle.standardError.write(Data("set AGENT_HOST, AGENT_USER, AGENT_KEY (and optionally AGENT_BRIDGE)\n".utf8))
        exit(2)
    }
    let bridge = env["AGENT_BRIDGE"] ?? "sudo /usr/local/bin/gryonixnexusd bridge"

    let keyString = try String(contentsOfFile: keyPath, encoding: .utf8)
    let privateKey = try Curve25519.Signing.PrivateKey(sshEd25519: keyString)

    let report = Report()
    report.note("connecting to \(user)@\(host) …")
    let client = try await SSHClient.connect(
        host: host,
        port: 22,
        authenticationMethod: .ed25519(username: user, privateKey: privateKey),
        hostKeyValidator: .acceptAnything(),
        reconnect: .never)
    defer { Task { try? await client.close() } }

    let agent = AgentClient(transport: SSHAgentTransport(client: client, bridgeCommand: bridge))

    if env["AGENT_SKIP_PHASE1"] == nil {
        await report.section("phase 1") { try await phase1(agent, client: client, bridge: bridge, report: report) }
    }
    if env["AGENT_SKIP_PHASE2"] == nil {
        await report.section("phase 2") { try await phase2(agent, report: report) }
    }
    await report.section("history") { try await historySection(agent, report: report) }
    await report.section("metrics board") { try await metricsBoardSection(agent, client: client, report: report) }
    await report.section("backups") { try await backupSection(agent, report: report) }
    await report.section("updates") { try await updateSection(agent, report: report) }
    await report.section("removal") { try await removalSection(agent, report: report) }
    await report.section("install") { try await installSection(agent, report: report) }
    await report.section("detached install") { try await detachedInstallSection(agent, report: report) }
    await report.section("no wrapper") { try await wrapperlessSection(client, report: report) }
    await report.section("admin guard") { try await lockdownSection(agent, report: report) }
    await report.section("restore") { try await restoreSection(agent, report: report) }
    await report.section("models") { try await modelsSection(agent, report: report) }
    await report.section("provider keys") { try await providerKeySection(agent, report: report) }
    await report.section("mailboxes") { try await mailboxSection(agent, report: report) }
    await report.section("vpn clients") { try await vpnClientSection(agent, report: report) }
    await report.section("mesh") { try await meshSection(agent, report: report) }
    await report.section("broken engine") { try await brokenEngineSection(client, bridge: bridge, report: report) }
    if env["AGENT_SKIP_GATE"] == nil {
        await report.section("gate") { try await gateSection(client, bridge: bridge, report: report) }
    } else {
        report.note("AGENT_SKIP_GATE set — the 16-concurrent-RPC negative control is not exercised " +
                     "(it trips OpenSSH's PerSourcePenalties against the caller's own IP, see GOTCHAS.md)")
    }
    report.finish()
}

if #available(macOS 15.0, *) {
    do {
        try await run()
    } catch {
        FileHandle.standardError.write(Data("FAILED: \(error)\n".utf8))
        exit(1)
    }
} else {
    FileHandle.standardError.write(Data("requires macOS 15+\n".utf8))
    exit(3)
}
