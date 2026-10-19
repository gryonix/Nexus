import Foundation
import ServerControl
import ServiceCatalog

/// What the demo fleet REMEMBERS between commands
actor DemoFleetState {
    static let shared = DemoFleetState()

    private var machines: [UUID: Machine] = [:]

    private init() {}

    /// Forgets everything
    func forgetEverything() { machines = [:] }

    // MARK: - What one demo machine remembers

    private struct Archive {
        var name: String
        var bytes: Int
        var made: Date
    }

    private struct Machine {
        /// Catalog ids whose containers are down
        var stopped: Set<String> = []
        var removed: Set<String> = []
        /// `off`, `on`, or `only <hosts>` — exactly what the wrapper prints
        var lockdown = "off"
        var mailboxes: [String]
        /// Per catalog id, newest first
        var archives: [String: [Archive]] = [:]
        /// Which services have an image waiting
        var updatable: Set<String>
        var backupSchedule = ""
        var updateSchedule = ""
        var lastUpdateRun = ""
    }

    private func machine(_ id: UUID, containers: [String]) -> Machine {
        if let existing = machines[id] { return existing }
        var seeded = Machine(
            mailboxes: ["you@\(Self.domain(for: id))", "family@\(Self.domain(for: id))"],
            updatable: Set(containers.prefix(2)))
        for id in containers.prefix(3) {
            seeded.archives[id] = [
                Archive(name: "\(id)-2026-08-16-0300.tar.gz", bytes: 4_812_544,
                        made: Date().addingTimeInterval(-7_200)),
                Archive(name: "\(id)-2026-08-09-0300.tar.gz", bytes: 4_755_100,
                        made: Date().addingTimeInterval(-611_000))
            ]
        }
        machines[id] = seeded
        return seeded
    }

    private static func domain(for id: UUID) -> String {
        switch id {
        case DemoServer.relayPairID: return "b.gryonix.com"
        case DemoServer.localOnlyID: return "home.local"
        case DemoServer.sshOnlyID: return "lab.gryonix.com"
        default: return DemoServer.domain
        }
    }

    // MARK: - What the demo agent reads and writes

    /// Which services are stopped, and which are gone
    func power(of deployment: UUID, containers: [String]) -> (stopped: Set<String>, removed: Set<String>) {
        let state = machine(deployment, containers: containers)
        return (state.stopped, state.removed)
    }

    func setPower(_ action: ServicePowerAction, service: String,
                  deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        switch action {
        case .stop: state.stopped.insert(service)
        case .start, .restart: state.stopped.remove(service)
        }
        machines[deployment] = state
    }

    func remove(service: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.removed.insert(service)
        state.stopped.remove(service)
        machines[deployment] = state
    }

    func install(service: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.removed.remove(service)
        state.stopped.remove(service)
        machines[deployment] = state
    }

    /// Newest first: name, bytes and date
    func archives(of service: String, deployment: UUID,
                  containers: [String]) -> [(name: String, bytes: Int, made: Date)] {
        machine(deployment, containers: containers).archives[service]?
            .map { ($0.name, $0.bytes, $0.made) } ?? []
    }

    @discardableResult
    func addArchive(service: String, deployment: UUID,
                    containers: [String]) -> (name: String, bytes: Int) {
        var state = machine(deployment, containers: containers)
        let made = Archive(name: "\(service)-\(Self.stamp()).tar.gz",
                           bytes: 4_900_000 + Int.random(in: 0..<400_000), made: Date())
        state.archives[service, default: []].insert(made, at: 0)
        machines[deployment] = state
        return (made.name, made.bytes)
    }

    func deleteArchive(named name: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        for (service, archives) in state.archives {
            state.archives[service] = archives.filter { $0.name != name }
        }
        machines[deployment] = state
    }

    func backupSchedule(of deployment: UUID, containers: [String]) -> String {
        machine(deployment, containers: containers).backupSchedule
    }

    func setBackupSchedule(_ value: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.backupSchedule = value
        machines[deployment] = state
    }

    func updateSchedule(of deployment: UUID, containers: [String]) -> String {
        machine(deployment, containers: containers).updateSchedule
    }

    func setUpdateSchedule(_ value: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.updateSchedule = value
        machines[deployment] = state
    }

    /// Which services have an image waiting
    func updatable(of deployment: UUID, containers: [String]) -> Set<String> {
        machine(deployment, containers: containers).updatable
    }

    func markUpdated(_ service: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.updatable.remove(service)
        state.lastUpdateRun = "\(CommandCatalog.Updates.updatedMarker) \(service)"
        machines[deployment] = state
    }

    func mailboxes(of deployment: UUID, containers: [String]) -> [String] {
        machine(deployment, containers: containers).mailboxes
    }

    func addMailbox(_ address: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        if !state.mailboxes.contains(address) { state.mailboxes.append(address) }
        machines[deployment] = state
    }

    func removeMailbox(_ address: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.mailboxes.removeAll { $0 == address }
        machines[deployment] = state
    }

    func lockdown(of deployment: UUID, containers: [String]) -> String {
        machine(deployment, containers: containers).lockdown
    }

    func setLockdown(_ value: String, deployment: UUID, containers: [String]) {
        var state = machine(deployment, containers: containers)
        state.lockdown = value
        machines[deployment] = state
    }

    // MARK: - The one entry point

    /// Answers a command, applying whatever it changes first
    func respond(to command: String, on host: SSHHostID,
                 deployment: UUID, containers: [String]) -> String {
        var state = machine(deployment, containers: containers)
        defer { machines[deployment] = state }
        let live = containers.filter { !state.removed.contains($0) }

        // --- things that change the machine ---

        if command.contains(CommandCatalog.Uninstall.scriptPath) {
            if let target = Self.argument(after: CommandCatalog.Uninstall.scriptPath, in: command) {
                if target == CommandCatalog.Uninstall.vpnTarget {
                    state.removed.formUnion(containers.filter { Self.isVPN($0) })
                } else {
                    state.removed.insert(target)
                }
            } else {
                state.removed.formUnion(containers)
            }
            return CommandCatalog.Uninstall.doneMarker
        }

        if command.contains(CommandCatalog.Restore.scriptPath) {
            return CommandCatalog.Restore.doneMarker
        }

        if command == CommandCatalog.AdminLockdown.status {
            return state.lockdown
        }
        if command == CommandCatalog.AdminLockdown.on { state.lockdown = "on"; return "" }
        if command == CommandCatalog.AdminLockdown.off { state.lockdown = "off"; return "" }
        if command.hasPrefix(CommandCatalog.AdminLockdown.only(hosts: [])) {
            let hosts = command
                .dropFirst(CommandCatalog.AdminLockdown.only(hosts: []).count)
                .trimmingCharacters(in: .whitespaces)
            state.lockdown = hosts.isEmpty ? "off" : "only \(hosts)"
            return ""
        }

        if command.contains(CommandCatalog.Backups.controlScriptPath) {
            return backupControl(command, state: &state, live: live)
        }

        if command.contains(CommandCatalog.Updates.controlScriptPath) {
            return updateControl(command, state: &state, live: live)
        }

        if command.contains(CommandCatalog.DockerMailserver.mailboxScriptPath) {
            return mailbox(command, state: &state)
        }

        if let (action, service) = Self.power(in: command, among: containers) {
            switch action {
            case .stop: state.stopped.insert(service)
            case .start, .restart: state.stopped.remove(service)
            }
            return ""
        }

        // --- things that only read ---

        if command.contains(CommandCatalog.Updates.readSchedule) { return state.updateSchedule }
        if command.contains("autobackup.conf") { return state.backupSchedule }

        if command.contains("ls -lht") {
            return listing(command, state: state, live: live)
        }

        if command.contains("docker compose"), command.contains(" ps") {
            return Self.composeTable(project: Self.project(in: command),
                                     containers: live, stopped: state.stopped)
        }
        if command.contains("docker ps") {
            return Self.dockerTable(containers: live, stopped: state.stopped)
        }
        if command.contains("docker logs") || command.contains("logs --tail") {
            return Self.log
        }
        if command.contains("install-report") {
            return Self.installReport
        }
        if let hostAnswer = Self.hostProbe(command, deployment: deployment, host: host) {
            return hostAnswer
        }
        return ""
    }

    // MARK: - The machine itself

    private static func hostProbe(_ command: String, deployment: UUID,
                                  host: SSHHostID) -> String? {
        if command.contains(CommandCatalog.generalProbeSeparator) {
            return [forwardingAnswer, pingAnswer(), pingAnswer()]
                .joined(separator: "\n\(CommandCatalog.generalProbeSeparator)\n")
        }
        if command.contains("@@STAT@@") { return nil }
        if command.contains(CommandCatalog.ipForwardingCheck) { return forwardingAnswer }
        if command.hasPrefix("ping ") { return pingAnswer() }
        if command.contains(CommandCatalog.wgShow) { return wgShowAnswer(host: host) }
        if command.contains(CommandCatalog.memory) {
            return freeAnswer(profile: profile(deployment, host))
        }
        if command.contains(CommandCatalog.disk) {
            return dfAnswer(profile: profile(deployment, host))
        }
        return nil
    }

    private static func profile(_ deployment: UUID, _ host: SSHHostID) -> DemoMachineProfile {
        DemoServer.profile(deploymentID: deployment, host: host) ?? .busyHost
    }

    private static let forwardingAnswer = "net.ipv4.ip_forward = 1"

    /// What `ping -c 1` prints
    private static func pingAnswer() -> String {
        """
        PING demo (203.0.113.20) 56(84) bytes of data.
        64 bytes from 203.0.113.20: icmp_seq=1 ttl=64 time=0.41 ms

        --- demo ping statistics ---
        1 packets transmitted, 1 received, 0% packet loss, time 0ms
        rtt min/avg/max/mdev = 0.410/0.410/0.410/0.000 ms
        """
    }

    private static func wgShowAnswer(host: SSHHostID) -> String {
        let isHome = host == .home
        return """
        interface: wg0
          public key: DEMO+SERVER+PLACEHOLDER+PUBLIC+KEY+0=
          private key: (hidden)
          listening port: 51820

        peer: DEMO+SERVER+PLACEHOLDER+PEER+KEY+00=
          endpoint: \(isHome ? "203.0.113.20:51820" : "198.51.100.7:51820")
          allowed ips: \(isHome ? "10.8.0.1/32" : "10.8.0.2/32")
          latest handshake: 42 seconds ago
          transfer: 1.21 GiB received, 3.45 GiB sent
          persistent keepalive: every 25 seconds
        """
    }

    private static func dfAnswer(profile: DemoMachineProfile) -> String {
        let size = profile.diskTotalBytes
        let used = Int64(Double(size) * profile.diskUsedFraction)
        let percent = Int((profile.diskUsedFraction * 100).rounded())
        return """
        Mounted on 1B-blocks Used Use%
        / \(size) \(used) \(percent)%
        /boot 536870912 96000000 18%
        """
    }

    private static func freeAnswer(profile: DemoMachineProfile) -> String {
        let total = profile.memTotalBytes
        let used = Int64(Double(total) * profile.memUsedFraction)
        let free = total - used
        let swapTotal = total / 4
        let swapUsed = total / 40
        return """
                       total        used        free      shared  buff/cache   available
        Mem: \(total) \(used) \(free) 0 \(total / 8) \(free)
        Swap: \(swapTotal) \(swapUsed) \(swapTotal - swapUsed)
        """
    }

    // MARK: - Wrappers

    private func backupControl(_ command: String, state: inout Machine, live: [String]) -> String {
        let done = CommandCatalog.Backups.controlDoneMarker
        if let service = Self.argument(after: "estimate", in: command) {
            let data = (state.archives[service]?.first?.bytes ?? 3_000_000) * 3
            return "\(CommandCatalog.Backups.estimateMarker) \(data) 41_000_000_000"
                .replacingOccurrences(of: "_", with: "") + "\n" + done
        }
        if command.contains(" delete ") {
            let path = Self.argument(after: "delete", in: command) ?? ""
            let name = (path as NSString).lastPathComponent
            for (service, archives) in state.archives {
                state.archives[service] = archives.filter { $0.name != name }
            }
            return done
        }
        if command.contains("set-schedule") {
            state.backupSchedule = Self.argument(after: "set-schedule", in: command) ?? "daily"
            return done
        }
        if command.contains("set-passphrase") { return done }
        guard let service = Self.argument(after: "run", in: command)
                ?? Self.argument(after: "backup", in: command),
              live.contains(service) else { return done }
        let name = "\(service)-\(Self.stamp()).tar.gz"
        let bytes = 4_900_000 + Int.random(in: 0..<400_000)
        state.archives[service, default: []].insert(
            Archive(name: name, bytes: bytes, made: Date()), at: 0)
        return """
        \(CommandCatalog.Backups.backupDoneMarker) \(bytes) /opt/backups/\(service)/\(name)
        \(done)
        """
    }

    private func updateControl(_ command: String, state: inout Machine, live: [String]) -> String {
        let done = CommandCatalog.Updates.doneMarker
        if command.contains(" status") {
            return state.lastUpdateRun.isEmpty
                ? "No scheduled run yet."
                : state.lastUpdateRun
        }
        if command.contains("set-schedule") {
            state.updateSchedule = Self.argument(after: "set-schedule", in: command) ?? "weekly"
            return done
        }
        if let service = Self.argument(after: "run", in: command) {
            state.updatable.remove(service)
            state.lastUpdateRun = "\(CommandCatalog.Updates.updatedMarker) \(service)"
            return """
            \(CommandCatalog.Updates.updatedMarker) \(service) \(service):latest
            \(done)
            """
        }
        let asked = Self.argument(after: "check", in: command)
        let services = (asked == nil || asked == "--all") ? live : [asked!]
        let lines = services.map { service in
            state.updatable.contains(service)
                ? "\(CommandCatalog.Updates.availableMarker) \(service) \(service):latest"
                : "\(CommandCatalog.Updates.currentMarker) \(service)"
        }
        return (lines + [done]).joined(separator: "\n")
    }

    private func mailbox(_ command: String, state: inout Machine) -> String {
        let marker = CommandCatalog.DockerMailserver.mailboxDoneMarker
        if command.contains(" list") {
            return state.mailboxes
                .map { "* \($0) ( 6.0K / ~ ) [0%]" }
                .joined(separator: "\n")
        }
        if let address = Self.argument(after: " add", in: command) {
            if !state.mailboxes.contains(address) { state.mailboxes.append(address) }
            return "\(marker) add \(address)"
        }
        if let address = Self.argument(after: " del", in: command) {
            state.mailboxes.removeAll { $0 == address }
            return "\(marker) del \(address)"
        }
        if let address = Self.argument(after: " password", in: command) {
            return "\(marker) password \(address)"
        }
        return marker
    }

    /// `ls -lht <dir>` for a backup directory
    private func listing(_ command: String, state: Machine, live: [String]) -> String {
        let service = live.first { command.contains("/\($0)") }
        let archives = service.flatMap { state.archives[$0] }
            ?? state.archives.values.flatMap { $0 }.sorted { $0.made > $1.made }
        guard !archives.isEmpty else { return "total 0" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm"
        let rows = archives.map { archive in
            "-rw-r--r-- 1 root root \(archive.bytes) \(formatter.string(from: archive.made)) \(archive.name)"
        }
        return (["total \(archives.count * 8)"] + rows).joined(separator: "\n")
    }

    // MARK: - Reading a command

    /// The word after a token, unquoted
    private static func argument(after token: String, in command: String) -> String? {
        guard let range = command.range(of: token + " ") else { return nil }
        let rest = command[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        let word = rest.prefix { !$0.isWhitespace }
        let unquoted = word.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return unquoted.hasPrefix("-") ? nil : unquoted
    }

    private static func power(in command: String,
                              among containers: [String]) -> (ServicePowerAction, String)? {
        let action: ServicePowerAction
        if command.contains(" restart") { action = .restart }
        else if command.contains(" stop") { action = .stop }
        else if command.contains(" start") { action = .start }
        else { return nil }
        guard let service = containers.first(where: { command.contains($0) }) else { return nil }
        return (action, service)
    }

    private static func isVPN(_ id: String) -> Bool {
        ServiceRegistry.service(ServiceID(rawValue: id))
            .map { $0.category == .vpn || $0.category == .implicit } ?? false
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    // MARK: - Canned reads

    private static func composeTable(project: String, containers: [String],
                                     stopped: Set<String>) -> String {
        let rows = containers.prefix(3).enumerated().map { index, name in
            pad("\(project)-\(name)-1", 34)
                + pad("\(name):latest", 26)
                + pad(status(of: name, stopped: stopped, index: index), 26)
                + "0.0.0.0:443->443/tcp"
        }
        return ([pad("NAME", 34) + pad("IMAGE", 26) + pad("STATUS", 26) + "PORTS"] + rows)
            .joined(separator: "\n")
    }

    private static func dockerTable(containers: [String], stopped: Set<String>) -> String {
        let rows = containers.enumerated().map { index, name in
            pad(String(format: "%012x", index &+ 0xd3_0000), 14)
                + pad("\(name):latest", 26)
                + pad(status(of: name, stopped: stopped, index: index), 26)
                + name
        }
        return ([pad("CONTAINER ID", 14) + pad("IMAGE", 26) + pad("STATUS", 26) + "NAMES"] + rows)
            .joined(separator: "\n")
    }

    private static func status(of name: String, stopped: Set<String>, index: Int) -> String {
        stopped.contains(name)
            ? "Exited (0) 4 seconds ago"
            : "Up \(3 + index) days (healthy)"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func project(in command: String) -> String {
        guard let range = command.range(of: "-p ") else { return "gryonixnexus" }
        let rest = command[range.upperBound...]
        return String(rest.prefix { !$0.isWhitespace })
    }

    private static let log = """
    2026-08-16T21:04:11.118Z Listening on 0.0.0.0:8080
    2026-08-16T21:04:11.402Z Database migrations are up to date
    2026-08-16T21:07:52.771Z GET /api/health 200 3ms
    2026-08-16T21:19:03.244Z Certificate for gryonix.com renewed, expires in 89 days
    2026-08-16T21:41:38.902Z GET /api/health 200 2ms
    """

    static let installReport = """
    GRYONIXNEXUS_REPORT
    Domain: gryonix.com
    Services: mail, passwords, files, photos, VPN, DNS filter
    Admin user: admin@gryonix.com
    This is the demo server. Its report is an example of what a real
    installation writes on the machine it installed.
    """
}
