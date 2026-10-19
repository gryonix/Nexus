import AgentClient
import Foundation

/// Demo plans that take time, fail and drop
actor DemoInstallPlans {
    static let shared = DemoInstallPlans()

    private struct Plan {
        let id: String
        let services: [String]
        let purpose: Gryonixnexusd_V1_InstallPlanPurpose
        let started: Date
    }

    private struct Line {
        let at: TimeInterval
        let phase: Gryonixnexusd_V1_JobPhase
        let text: String
    }

    private var plans: [Plan] = []
    private var dropped = false

    /// Seconds one service takes in the demo
    static let serviceSeconds: TimeInterval = 2.5

    static let caddyFailure =
        "Caddy refused the new sites, so the previous ones were put back. Caddy said: no_such_directive is not a known directive"

    /// Launch argument naming the service whose site fails
    private static var failing: String { UserDefaults.standard.string(forKey: "GRYONIX_DEMO_PLAN_FAIL") ?? "" }

    /// Launch argument: events read before the line drops once
    private static var dropAfter: Int { UserDefaults.standard.integer(forKey: "GRYONIX_DEMO_PLAN_DROP") }

    func start(_ services: [String], purpose: Gryonixnexusd_V1_InstallPlanPurpose) throws -> Gryonixnexusd_V1_InstallPlan {
        if let last = plans.last, !isFinished(last) {
            throw AgentError.rpc(code: "already_exists", message: "an install plan is already running on this host")
        }
        let plan = Plan(id: "demo-plan-\(plans.count + 1)", services: services, purpose: purpose, started: Date())
        plans.append(plan)
        return wire(plan)
    }

    func get(_ id: String) -> Gryonixnexusd_V1_InstallPlan {
        let found = id.isEmpty ? plans.last : plans.first { $0.id == id }
        return found.map(wire) ?? Gryonixnexusd_V1_InstallPlan()
    }

    func owns(_ jobID: String) -> Bool { plans.contains { $0.id == jobID } }

    /// The plan's log as timed steps from a sequence on
    func log(_ id: String, from sequence: UInt64) -> [DemoAgentStep] {
        guard let plan = plans.first(where: { $0.id == id }) else { return [] }
        let now = Date().timeIntervalSince(plan.started)
        var steps: [DemoAgentStep] = []
        var clock = now
        for (index, line) in lines(of: plan).enumerated() where UInt64(index) >= sequence {
            if Self.dropAfter > 0, !dropped, steps.count == Self.dropAfter {
                dropped = true
                steps.append(DemoAgentStep(payload: Data(), delay: 0, drops: true))
                return steps
            }
            var event = Gryonixnexusd_V1_JobEvent()
            event.jobID = plan.id
            event.sequence = UInt64(index)
            event.phase = line.phase
            event.stream = "agent"
            event.text = line.text
            steps.append(event.demoStep(delay: Int(max(0, line.at - clock) * 1000)))
            clock = max(clock, line.at)
        }
        return steps
    }

    private func lines(of plan: Plan) -> [Line] {
        var out: [Line] = []
        for (index, id) in plan.services.enumerated() {
            let begin = Double(index) * Self.serviceSeconds
            out.append(Line(at: begin, phase: .progress, text: "GRYONIXNEXUS_STEP \(index + 1)/\(plan.services.count)\n\(id)"))
            out.append(Line(at: begin + 0.5, phase: .progress, text: "pulling the \(id) image"))
            out.append(Line(at: begin + 1.2, phase: .progress, text: "starting \(id)"))
            out.append(Line(at: begin + 1.8, phase: .progress, text: "reloading Caddy"))
            if id == Self.failing {
                out.append(Line(at: begin + 2.2, phase: .progress, text: "\(id): \(Self.caddyFailure)"))
            }
        }
        out.append(Line(at: Double(plan.services.count) * Self.serviceSeconds, phase: .completed, text: ""))
        return out
    }

    private func isFinished(_ plan: Plan) -> Bool {
        Date().timeIntervalSince(plan.started) >= Double(plan.services.count) * Self.serviceSeconds
    }

    private func wire(_ plan: Plan) -> Gryonixnexusd_V1_InstallPlan {
        let settled = Int(Date().timeIntervalSince(plan.started) / Self.serviceSeconds)
        var wire = Gryonixnexusd_V1_InstallPlan()
        wire.planID = plan.id
        wire.purpose = plan.purpose
        wire.finished = settled >= plan.services.count
        wire.items = plan.services.enumerated().map { index, id in
            var item = Gryonixnexusd_V1_InstallPlanItem()
            item.serviceID = id
            item.jobID = index <= settled ? "\(plan.id)-\(index)" : ""
            if index < settled {
                item.state = id == Self.failing ? .failed : .done
                item.failure = id == Self.failing ? Self.caddyFailure : ""
            } else {
                item.state = index == settled ? .running : .pending
            }
            return item
        }
        return wire
    }
}
