import Foundation
import ServerControl
import ServiceCatalog

/// Which host's processes to list
struct TopProcessesTarget: Hashable {
    let deployment: Deployment
    let host: SSHHostID
}

/// Reads `top` on one host every few seconds
@MainActor
final class TopProcessesModel: ObservableObject {
    @Published private(set) var samples: [ProcessSample] = []
    @Published private(set) var loaded = false
    @Published private(set) var errorMessage: String?

    let target: TopProcessesTarget
    static let interval: Duration = .seconds(5)

    init(target: TopProcessesTarget) { self.target = target }

    /// Refreshes until the screen goes away
    func follow() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.interval)
        }
    }

    private func refresh() async {
        do {
            let output = try await read()
            samples = TopProcesses.parse(output)
            errorMessage = samples.isEmpty ? UIL10n.string("The server did not list its processes.") : nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        loaded = true
    }

    private func read() async throws -> String {
        #if DEBUG
        if DemoFleet.covers(target.deployment) { return DemoProcesses.output }
        #endif
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: target.deployment)
        return try await runner.run(TopProcesses.command, on: target.host, timeout: .seconds(20)).stdout
    }
}

#if DEBUG
/// A plausible `top` for demo servers
enum DemoProcesses {
    static let output = """
    top - 12:00:00 up 3 days
        PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
       2101 root      20   0 2530784 816960  17376 S  12.0   5.0  17:26.49 python3 -P -m homeassistant --config /config
       1402 999       20   0  402000 402100   9000 S   6.5   2.5   9:00.00 postgres: immich immich idle
       1403 999       20   0  202000 202100   9000 S   1.5   1.2   2:00.00 postgres: checkpointer
        930 root      20   0 1200000 131072  30000 S   3.0   0.8   4:00.00 /usr/bin/dockerd -H fd://
        933 www-data  20   0  300000  96000  20000 S   2.0   0.6   1:00.00 php-fpm: pool www
        934 www-data  20   0  300000  94000  20000 S   1.0   0.6   1:00.00 php-fpm: pool www
        700 root      20   0  900000  61440  12000 S   0.5   0.4   3:00.00 /usr/bin/caddy run --config /etc/caddy/Caddyfile
        650 root      20   0   90000  20480   8000 S   0.5   0.1   2:00.00 /usr/local/bin/gryonixnexusd
        640 1883      20   0   12000   8192   4000 S   0.0   0.1   0:10.00 /usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf
         17 root      20   0       0      0      0 S   0.3   0.0   0:10.61 [ksoftirqd/0]
    """
}
#endif
