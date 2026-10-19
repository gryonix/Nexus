import Foundation
import ServerControl
import ServiceCatalog

public struct ServiceMovePlan: Sendable {
    public let service: ServiceID
    public let target: ServiceMoveEndpoint
    public let sourceEntryAddress: String?
    public let targetEntryAddress: String?
    public let localPort: UInt32
    public let localHTTPS: Bool
    public let overwriteForwardedFor: Bool
    public let installContext: AgentInstallContext

    public init(service: ServiceID, target: ServiceMoveEndpoint, sourceEntryAddress: String?,
                targetEntryAddress: String?, localPort: UInt32, localHTTPS: Bool,
                overwriteForwardedFor: Bool, installContext: AgentInstallContext) {
        self.service = service
        self.target = target
        self.sourceEntryAddress = sourceEntryAddress
        self.targetEntryAddress = targetEntryAddress
        self.localPort = localPort
        self.localHTTPS = localHTTPS
        self.overwriteForwardedFor = overwriteForwardedFor
        self.installContext = installContext
    }
}

public enum ServiceMoveProblem: Error, Equatable, Sendable {
    case notOnSource
    case alreadyOnTarget
    case noSiteOnFront
    case frontDisagrees(String)
    case notAnswering(status: Int32, detail: String)
    case noArchive
    case noLoginAccess
}

public enum ServiceMoveEvent: Sendable, Equatable {
    case step(ServiceMoveStep)
    case log(String)
    case undoing
}

/// What undoing a failed move managed to do
public struct ServiceMoveUndo: Sendable, Equatable {
    public var entryRestored = false
    public var sourceStarted = false
    public var targetCopyRemoved = false
    public var problems: [String] = []

    public init() {}
}

public struct ServiceMoveFailure: Error, Sendable {
    public let step: ServiceMoveStep
    public let underlying: any Error
    public let undone: ServiceMoveUndo
}

public actor ServiceMoveRunner {
    private let plan: ServiceMovePlan
    private let source: any ServiceMoveMachine
    private let target: any ServiceMoveMachine
    private let front: any ServiceMoveMachine
    private let onRecord: @Sendable (ServiceMoveRecord) -> Void
    private let onEvent: @Sendable (ServiceMoveEvent) -> Void
    private var record: ServiceMoveRecord

    public init(plan: ServiceMovePlan, record: ServiceMoveRecord,
                source: any ServiceMoveMachine, target: any ServiceMoveMachine,
                front: any ServiceMoveMachine,
                onRecord: @escaping @Sendable (ServiceMoveRecord) -> Void,
                onEvent: @escaping @Sendable (ServiceMoveEvent) -> Void) {
        self.plan = plan
        self.record = record
        self.source = source
        self.target = target
        self.front = front
        self.onRecord = onRecord
        self.onEvent = onEvent
    }

    public func run() async throws {
        let stages: [(ServiceMoveStep, () async throws -> Void)] = [
            (.check, check), (.install, install), (.backup, backUp), (.stop, stop), (.send, send),
            (.restore, restore), (.switchEntry, switchEntry), (.verify, verify), (.finish, finish)
        ]
        for (step, work) in stages where step >= record.step {
            enter(step)
            do {
                try await work()
            } catch {
                throw ServiceMoveFailure(step: step, underlying: error, undone: await undo())
            }
        }
    }

    public func undo() async -> ServiceMoveUndo {
        onEvent(.undoing)
        var done = ServiceMoveUndo()
        if record.switchedEntry {
            done.entryRestored = await attempt("pointing the site back") { [self] in
                _ = try await front.site(siteChange(remote: plan.sourceEntryAddress))
            }
        }
        if record.sourceStopped {
            done.sourceStarted = await attempt("starting the old copy") { [self] in
                try await source.start(plan.service, log: log)
            }
        }
        if record.installedOnTarget {
            done.targetCopyRemoved = await attempt("removing the new copy") { [self] in
                try await target.removeCopy(plan.service, log: log)
            }
        }
        await cleanUpTransfer()
        done.problems = problems
        return done
    }

    private var problems: [String] = []

    private var log: ServiceMoveLog { { [onEvent] text in onEvent(.log(text)) } }

    private func enter(_ step: ServiceMoveStep) {
        record.step = step
        onRecord(record)
        onEvent(.step(step))
    }

    private func save(_ change: (inout ServiceMoveRecord) -> Void) {
        change(&record)
        onRecord(record)
    }

    private func attempt(_ what: String, _ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            return true
        } catch {
            problems.append("\(what): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            return false
        }
    }

    private func siteChange(remote: String?, dryRun: Bool = false) -> ServiceMoveSiteChange {
        ServiceMoveSiteChange(service: plan.service, localPort: plan.localPort, localHTTPS: plan.localHTTPS,
                              overwriteForwardedFor: plan.overwriteForwardedFor,
                              remoteAddress: remote, dryRun: dryRun)
    }

    // MARK: - Stages

    private func check() async throws {
        guard try await source.hasService(plan.service) else { throw ServiceMoveProblem.notOnSource }
        if try await target.hasService(plan.service) { throw ServiceMoveProblem.alreadyOnTarget }
        let expected: ServiceMoveSite = plan.sourceEntryAddress.map { .remote($0) } ?? .local
        let found = try await front.site(siteChange(remote: plan.sourceEntryAddress, dryRun: true))
        if found == .missing { throw ServiceMoveProblem.noSiteOnFront }
        if found != expected { throw ServiceMoveProblem.frontDisagrees(Self.words(found)) }
        let bytes = try await source.estimatedBytes(of: plan.service)
        onEvent(.log("about \(bytes) bytes of data"))
    }

    private func install() async throws {
        save { $0.installedOnTarget = true }
        try await target.install(plan.service, context: plan.installContext, log: log)
    }

    private func backUp() async throws {
        let archive = try await source.backUp(plan.service, log: log)
        save { $0.archivePath = archive.path; $0.archiveName = archive.name; $0.archiveBytes = archive.bytes }
    }

    private func stop() async throws {
        save { $0.sourceStopped = true }
        try await source.stop(plan.service, log: log)
    }

    private func send() async throws {
        guard let path = record.archivePath, record.archiveName != nil else { throw ServiceMoveProblem.noArchive }
        let id = record.transferID
        let key = try await source.prepareSend(transferID: id)
        let grant = try await target.prepareReceive(transferID: id, service: plan.service, publicKey: key,
                                                    expectedBytes: record.archiveBytes ?? 0)
        try await target.authorize(grant)
        do {
            let sent = try await source.send(transferID: id, service: plan.service, archivePath: path,
                                             to: plan.target, hostKeys: grant.hostKeys, log: log)
            save { $0.sha256 = sent.sha256; $0.sentBytes = sent.bytes; $0.archiveName = sent.archiveName }
        } catch {
            try? await target.revoke(transferID: id)
            throw error
        }
        try? await target.revoke(transferID: id)
    }

    private func restore() async throws {
        guard let name = record.archiveName, let sha = record.sha256, let bytes = record.sentBytes else {
            throw ServiceMoveProblem.noArchive
        }
        let sent = ServiceMoveSent(bytes: bytes, sha256: sha, archiveName: name)
        let path = try await target.accept(transferID: record.transferID, service: plan.service,
                                           sent: sent, log: log)
        save { $0.targetArchivePath = path }
        try await target.restore(plan.service, archivePath: path, log: log)
    }

    private func switchEntry() async throws {
        save { $0.switchedEntry = true }
        _ = try await front.site(siteChange(remote: plan.targetEntryAddress))
    }

    private func verify() async throws {
        let answer = try await front.probe(plan.service)
        if answer.unavailable {
            onEvent(.log("could not check the site: \(answer.detail)"))
        } else if !answer.answered {
            throw ServiceMoveProblem.notAnswering(status: answer.status, detail: answer.detail)
        }
    }

    private func finish() async throws {
        await cleanUpTransfer()
        if let path = record.targetArchivePath {
            try? await target.deleteBackup(plan.service, path: path)
        }
    }

    private func cleanUpTransfer() async {
        let id = record.transferID
        try? await target.revoke(transferID: id)
        try? await source.discard(transferID: id)
        try? await target.discard(transferID: id)
    }

    private static func words(_ site: ServiceMoveSite) -> String {
        switch site {
        case .local: return "local"
        case .remote(let address): return address
        case .missing: return "missing"
        case .unknown: return "unknown"
        }
    }
}
