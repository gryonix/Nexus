import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

/// Follows an agent's install plan to its end
@available(macOS 15.0, *)
struct InstallPlanFollower {
    var installer: AgentInstallOperations
    var purpose: AgentPlanPurpose = .add
    let onStage: @MainActor (String) -> Void
    let onProgress: @MainActor (_ settled: Int, _ total: Int) -> Void
    let onChunk: @Sendable (String) -> Void
    let onWarning: @Sendable (String) -> Void
    var pause: Duration = .seconds(2)
    /// How far the plan's log has been read
    var mark = PlanLogMark()

    /// Starts the list, or joins the plan already running
    func start(_ services: [(ServiceID, AgentInstallContext)]) async throws -> AgentInstallPlan {
        do {
            return try await installer.startPlan(services, purpose: purpose)
        } catch AgentError.rpc(code: "already_exists", _) {
            return try await installer.plan()
        }
    }

    /// The plan as it ended; a drop resumes reading
    func follow(_ started: AgentInstallPlan) async throws -> AgentInstallPlan {
        var plan = started
        while true {
            await onProgress(plan.settled, plan.items.count)
            try await installer.watchPlan(plan.id, from: mark.next) { next, stream, text in
                mark.next = next
                show(text, stream: stream)
            }
            plan = try await installer.plan(plan.id)
            if plan.id != started.id { throw InstallStepFailure(message: Self.lostMessage) }
            if plan.finished {
                await onProgress(plan.settled, plan.items.count)
                return plan
            }
            try await Task.sleep(for: pause)
        }
    }

    private func show(_ text: String, stream: String) {
        if let step = Self.step(text) {
            let stage = stageText(Self.displayName(step.service))
            Task { @MainActor in
                onStage(stage)
                onProgress(step.index - 1, step.total)
            }
        } else if !text.isEmpty {
            onChunk(text.hasSuffix("\n") ? text : text + "\n")
            if stream == "warning" { onWarning(text) }
        }
    }

    private func stageText(_ name: String) -> String {
        switch purpose {
        case .repair: UIL10n.string("Repairing %@", name)
        case .reinstall: UIL10n.string("Reinstalling %@", name)
        case .add, .setup: UIL10n.string("Installing %@…", name)
        }
    }

    /// The agent's step marker: number, total and service
    static func step(_ text: String) -> (index: Int, total: Int, service: String)? {
        guard text.hasPrefix("GRYONIXNEXUS_STEP ") else { return nil }
        let lines = text.dropFirst("GRYONIXNEXUS_STEP ".count).split(separator: "\n", maxSplits: 1)
        let counts = lines.first?.split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? []
        guard counts.count == 2, lines.count == 2 else { return nil }
        return (counts[0], counts[1], String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The agent restarted and forgot the plan
    static var lostMessage: String {
        UIL10n.string("The agent restarted during the installation and lost its list. Start the installation again: what is already installed is skipped.")
    }

    static func displayName(_ agentServiceID: String) -> String {
        if agentServiceID == "vpn" { return "VPN" }
        return ServiceRegistry.service(ServiceID(rawValue: agentServiceID))?.displayName ?? agentServiceID
    }

    /// Names the services the plan left uninstalled
    static func failureMessage(_ plan: AgentInstallPlan) -> String? {
        let missed = plan.items.filter { $0.state == .failed || $0.state == .skipped }
        guard !missed.isEmpty else { return nil }
        let names = missed.map { displayName($0.agentServiceID) }.joined(separator: ", ")
        return UIL10n.string("Not installed: %@. Start the installation again to retry them.", names)
    }

    /// Whether a mail server came up
    static func installedMail(_ plan: AgentInstallPlan) -> Bool {
        let mail = [ServiceID.mailcow, .mailu, .dockerMailserver].map(\.rawValue)
        return plan.items.contains { $0.state == .done && mail.contains($0.agentServiceID) }
    }
}

/// The next log line to ask the agent for
final class PlanLogMark: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var next: UInt64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
