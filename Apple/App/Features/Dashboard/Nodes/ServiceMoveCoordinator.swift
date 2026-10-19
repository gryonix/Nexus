import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

@available(macOS 15.0, *)
@MainActor
final class ServiceMoveCoordinator {
    private static var running: Set<UUID> = []

    static func isRunning(deployment: UUID) -> Bool { running.contains(deployment) }

    private let deployment: Deployment
    private let route: ServiceMoveRoute
    private let service: any ManagedService
    private let store = ServiceMoveStore()
    private let onPlaced: (Deployment) -> Void
    private let onSettled: () -> Void
    private let operation: LongOperationState
    private var record: ServiceMoveRecord
    private var closed = false

    init?(deployment: Deployment, route: ServiceMoveRoute, resuming: ServiceMoveRecord? = nil,
          onPlaced: @escaping (Deployment) -> Void, onSettled: @escaping () -> Void) {
        guard let service = ServiceRegistry.service(route.service) else { return nil }
        self.deployment = deployment
        self.route = route
        self.service = service
        self.onPlaced = onPlaced
        self.onSettled = onSettled
        self.record = resuming ?? ServiceMoveRecord(
            deployment: deployment.id, service: route.service, source: route.source.id,
            target: route.target.id, transferID: Self.newTransferID())
        self.operation = LongOperationState(
            title: UIL10n.string("Moving %1$@ to %2$@", service.displayName, Self.name(of: route.target)),
            progressText: UIL10n.string("Checking both machines…"))
    }

    private static func newTransferID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func name(of node: DeploymentNode) -> String {
        node.name.isEmpty ? node.endpoint.host : node.name
    }

    func start() {
        begin()
        Task { await run() }
    }

    func putBack() {
        begin()
        operation.progressText = UIL10n.string("Putting everything back…")
        Task { await undo() }
    }

    private func begin() {
        Self.running.insert(deployment.id)
        store.save(record)
        RunningOperationsRegistry.shared.start(operation, serverName: deployment.name, deployment: deployment)
    }

    // MARK: - Running

    private func run() async {
        defer { settle() }
        do {
            let runner = try await makeRunner()
            try await runner.run()
            succeed()
        } catch let failure as ServiceMoveFailure {
            fail(UIL10n.string("The move did not finish") + "\n" +
                 ServiceMoveWording.failure(failure, serviceName: service.displayName),
                 keepRecord: !failure.undone.problems.isEmpty)
        } catch {
            fail(UIL10n.string("The move did not finish") + "\n" +
                 ServiceMoveWording.reason(of: error, serviceName: service.displayName), keepRecord: record.step > .check)
        }
    }

    private func undo() async {
        defer { settle() }
        closed = true
        do {
            let runner = try await makeRunner()
            let undone = await runner.undo()
            if undone.problems.isEmpty {
                store.clear(deployment: deployment.id)
                operation.progressText = UIL10n.string("Everything is back as it was.")
            } else {
                operation.errorMessage = UIL10n.string("Not everything could be put back: %@",
                                                       undone.problems.joined(separator: "; "))
            }
        } catch {
            operation.errorMessage = ServiceMoveWording.reason(of: error, serviceName: service.displayName)
        }
        operation.isFinished = true
    }

    private func succeed() {
        closed = true
        var updated = deployment
        updated.place(route.service, on: route.target.id)
        store.clear(deployment: deployment.id)
        operation.progress = 1
        operation.progressText = UIL10n.string("%1$@ now runs on %2$@. The old copy is stopped and its data kept.",
                                               service.displayName, Self.name(of: route.target))
        operation.isFinished = true
        onPlaced(updated)
    }

    private func fail(_ message: String, keepRecord: Bool) {
        closed = true
        if !keepRecord { store.clear(deployment: deployment.id) }
        operation.errorMessage = message
        operation.isFinished = true
    }

    private func settle() {
        Self.running.remove(deployment.id)
        onSettled()
    }

    // MARK: - Machines

    private func makeRunner() async throws -> ServiceMoveRunner {
        let session = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment, shared: false)
        var machines: [UUID: AgentServiceMoveMachine] = [:]
        func machine(_ node: DeploymentNode) async throws -> AgentServiceMoveMachine {
            if let known = machines[node.id] { return known }
            let client = try await AgentConnection.client(deployment: deployment, runner: session, host: node.sshHost)
            let shell = SSHMoveShell(runner: session, host: node.sshHost, loginUser: deployment.entry.user)
            let made = AgentServiceMoveMachine(client: client, shell: shell)
            machines[node.id] = made
            return made
        }
        let plan = try await makePlan()
        return ServiceMoveRunner(
            plan: plan, record: record,
            source: try await machine(route.source), target: try await machine(route.target),
            front: try await machine(route.front),
            onRecord: { [weak self] saved in Task { @MainActor in self?.recorded(saved) } },
            onEvent: { [weak self] event in Task { @MainActor in self?.heard(event) } })
    }

    private func makePlan() async throws -> ServiceMovePlan {
        guard let ingress = service.webIngress(deployment.serviceContext) else {
            throw ServiceMoveRefusal.notMovable(route.service)
        }
        let key = await DashboardViewModel.devicePublicKey(for: deployment)
        var context = DashboardViewModel.agentHostSurfaceContext(for: deployment, devicePublicKey: key)
        if !route.targetIsFront {
            context.localOnly = true
            context.host = AgentHostSurface(role: .singleHost, dashboardPublicKey: key)
        }
        let target = route.target
        let port = target.legacySlot == nil ? target.endpoint.port : deployment.entry.port
        return ServiceMovePlan(
            service: route.service,
            target: ServiceMoveEndpoint(host: target.endpoint.host, port: UInt32(port), user: deployment.entry.user),
            sourceEntryAddress: route.sourceEntryAddress, targetEntryAddress: route.targetEntryAddress,
            localPort: UInt32(ingress.upstreamPort), localHTTPS: ingress.upstreamHTTPS,
            overwriteForwardedFor: ingress.overwriteForwardedFor, installContext: context)
    }

    private func recorded(_ saved: ServiceMoveRecord) {
        guard !closed else { return }
        record = saved
        store.save(saved)
        operation.progress = Double(saved.step.rawValue) / Double(ServiceMoveStep.allCases.count)
    }

    private func heard(_ event: ServiceMoveEvent) {
        switch event {
        case .step(let step):
            operation.progressText = ServiceMoveWording.stepText(step)
        case .log(let text):
            let line = text.hasSuffix("\n") ? text : text + "\n"
            operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + line), maxCharacters: OutputTail.logCharacters)
        case .undoing:
            operation.progressText = UIL10n.string("Putting everything back…")
        }
    }
}
