import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf

extension DemoAgentState {
    /// Metrics, logs and the operations that report while they run
    func controlStream(_ path: String, _ request: Data,
                       _ machine: DemoAgentMachine) async throws -> [DemoAgentStep]? {
        switch path {
        case "/gryonixnexusd.v1.Control/HostMetrics":
            return Self.metricsSamples(machine).map { $0.demoStep(delay: 1_000) }
        case "/gryonixnexusd.v1.Control/Logs":
            let asked = try Gryonixnexusd_V1_LogsRequest(serializedBytes: request)
            return Self.logLines(service: asked.serviceID).map { $0.demoStep(delay: 120) }
        case "/gryonixnexusd.v1.Control/ControlService":
            let asked = try Gryonixnexusd_V1_ControlServiceRequest(serializedBytes: request)
            return try await controlService(asked, machine)
        case "/gryonixnexusd.v1.Security/ControlSecurity":
            let asked = try Gryonixnexusd_V1_ControlSecurityRequest(serializedBytes: request)
            return securityRun(asked, machine)
        case "/gryonixnexusd.v1.AgentUpdate/ApplyAgentUpdate":
            return Self.agentUpdateRun()
        default:
            return nil
        }
    }

    private static func metricsSamples(_ machine: DemoAgentMachine) -> [Gryonixnexusd_V1_MetricsSample] {
        let profile = DemoServer.profile(deploymentID: machine.id, host: .vps) ?? .busyHost
        return (0..<6).map { index in
            var sample = Gryonixnexusd_V1_MetricsSample()
            sample.sampledAt = Int64(Date().timeIntervalSince1970 * 1000)
            sample.cpuCores = 4
            sample.cpuPercent = 16 + Double(index) * 2
            sample.memTotalBytes = profile.memTotalBytes
            sample.memUsedBytes = Int64(Double(profile.memTotalBytes) * profile.memUsedFraction)
            sample.uptimeSeconds = 986_400
            sample.load1 = 0.7
            sample.load5 = 0.6
            sample.load15 = 0.5
            sample.netReceivedBytes = 8_100_000_000
            sample.netSentBytes = 3_400_000_000
            var mount = Gryonixnexusd_V1_DiskMount()
            mount.target = "/"
            mount.sizeBytes = profile.diskTotalBytes
            mount.usedBytes = Int64(Double(profile.diskTotalBytes) * profile.diskUsedFraction)
            sample.mounts = [mount]
            return sample
        }
    }

    private static func logLines(service: String) -> [Gryonixnexusd_V1_LogLine] {
        let texts = ["Listening on 0.0.0.0:8080",
                     "Database migrations are up to date",
                     "GET /api/health 200 3ms",
                     "Certificate renewed, expires in 89 days",
                     "GET /api/health 200 2ms"]
        return texts.map { text in
            var line = Gryonixnexusd_V1_LogLine()
            line.serviceID = service
            line.at = Int64(Date().timeIntervalSince1970 * 1000)
            line.stream = "stdout"
            line.text = text
            line.container = "\(service)-app-1"
            return line
        }
    }

    // MARK: - Starting and stopping things

    private func controlService(_ asked: Gryonixnexusd_V1_ControlServiceRequest,
                                _ machine: DemoAgentMachine) async throws -> [DemoAgentStep] {
        let action: ServicePowerAction
        switch asked.action {
        case .stop: action = .stop
        case .restart: action = .restart
        default: action = .start
        }
        await DemoFleetState.shared.setPower(action, service: asked.serviceID,
                                             deployment: machine.id,
                                             containers: machine.containers)
        let verb = action == .stop ? "Stopping" : (action == .restart ? "Restarting" : "Starting")
        var steps = Self.progressLines(asked.serviceID, verb: verb).map { text -> DemoAgentStep in
            var event = Gryonixnexusd_V1_ServiceOperationEvent()
            event.phase = .progress
            event.serviceID = asked.serviceID
            event.action = asked.action
            event.text = text
            event.stream = "stdout"
            return event.demoStep()
        }
        var done = Gryonixnexusd_V1_ServiceOperationEvent()
        done.phase = .completed
        done.serviceID = asked.serviceID
        done.action = asked.action
        steps.append(done.demoStep())
        return steps
    }

    private func securityRun(_ asked: Gryonixnexusd_V1_ControlSecurityRequest,
                             _ machine: DemoAgentMachine) -> [DemoAgentStep] {
        let bans = asked.action == .remove ? [] : memory(machine).bans
        var steps = Self.progressLines("CrowdSec", verb: Self.verb(asked.action))
            .map { text -> DemoAgentStep in
                var event = Gryonixnexusd_V1_SecurityOperationEvent()
                event.phase = .progress
                event.action = asked.action
                event.text = text
                event.stream = "stdout"
                return event.demoStep()
            }
        var done = Gryonixnexusd_V1_SecurityOperationEvent()
        done.phase = .completed
        done.action = asked.action
        var status = Self.securityStatus(bans: bans)
        status.present = asked.action != .remove
        status.engineRunning = asked.action != .stop && asked.action != .remove
        done.status = status
        steps.append(done.demoStep())
        return steps
    }

    private static func verb(_ action: Gryonixnexusd_V1_SecurityAction) -> String {
        switch action {
        case .stop: return "Stopping"
        case .restart: return "Restarting"
        case .update: return "Updating"
        case .install: return "Installing"
        case .remove: return "Removing"
        default: return "Starting"
        }
    }

    private static func agentUpdateRun() -> [DemoAgentStep] {
        var steps = ["Fetching the agent sources", "Building", "Restarting the service"]
            .map { text -> DemoAgentStep in
                var event = Gryonixnexusd_V1_AgentUpdateEvent()
                event.phase = .progress
                event.text = text
                return event.demoStep(delay: 500)
            }
        var done = Gryonixnexusd_V1_AgentUpdateEvent()
        done.phase = .completed
        steps.append(done.demoStep())
        return steps
    }
}
