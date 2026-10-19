import Foundation
import ServerControl
import ServiceCatalog
import XCTest
@testable import AgentControl

private final class Tape: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}

private struct Boom: Error, LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

private final class FakeMachine: ServiceMoveMachine, @unchecked Sendable {
    let name: String
    let tape: Tape
    var has = false
    var failing: Set<String> = []
    var site: ServiceMoveSite = .local
    var probeAnswer = ServiceMoveProbe(answered: true, unavailable: false, status: 200, detail: "")
    private(set) var changes: [ServiceMoveSiteChange] = []

    init(_ name: String, tape: Tape, has: Bool = false) {
        self.name = name
        self.tape = tape
        self.has = has
    }

    private func call(_ what: String) throws {
        tape.add("\(name).\(what)")
        if failing.contains(what) { throw Boom(text: "\(name) \(what) failed") }
    }

    func hasService(_ service: ServiceID) async throws -> Bool { try call("has"); return has }
    func estimatedBytes(of service: ServiceID) async throws -> Int64 { try call("estimate"); return 1000 }
    func install(_ service: ServiceID, context: AgentInstallContext, log: @escaping ServiceMoveLog) async throws {
        try call("install")
    }
    func backUp(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws -> ServiceMoveArchive {
        try call("backup")
        return ServiceMoveArchive(path: "/b/a.tar.gz", name: "a.tar.gz", bytes: 500)
    }
    func start(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws { try call("start") }
    func stop(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws { try call("stop") }
    func restore(_ service: ServiceID, archivePath: String, log: @escaping ServiceMoveLog) async throws {
        try call("restore:\(archivePath)")
    }
    func removeCopy(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws { try call("removeCopy") }
    func deleteBackup(_ service: ServiceID, path: String) async throws { try call("deleteBackup:\(path)") }
    func prepareSend(transferID: String) async throws -> String { try call("prepareSend"); return "ssh-ed25519 KEY" }
    func prepareReceive(transferID: String, service: ServiceID, publicKey: String,
                        expectedBytes: Int64) async throws -> ServiceMoveGrant {
        try call("prepareReceive:\(publicKey):\(expectedBytes)")
        return ServiceMoveGrant(authorizedKeyLine: "LINE", hostKeys: "ssh-ed25519 HOST", freeBytes: 9)
    }
    func authorize(_ grant: ServiceMoveGrant) async throws { try call("authorize:\(grant.authorizedKeyLine)") }
    func revoke(transferID: String) async throws { try call("revoke") }
    func send(transferID: String, service: ServiceID, archivePath: String, to target: ServiceMoveEndpoint,
              hostKeys: String, log: @escaping ServiceMoveLog) async throws -> ServiceMoveSent {
        try call("send:\(archivePath)->\(target.host):\(hostKeys)")
        return ServiceMoveSent(bytes: 520, sha256: "abc", archiveName: "a.tar.gz")
    }
    func accept(transferID: String, service: ServiceID, sent: ServiceMoveSent,
                log: @escaping ServiceMoveLog) async throws -> String {
        try call("accept:\(sent.sha256):\(sent.bytes)")
        return "/new/a.tar.gz"
    }
    func discard(transferID: String) async throws { try call("discard") }
    func site(_ change: ServiceMoveSiteChange) async throws -> ServiceMoveSite {
        try call(change.dryRun ? "siteCheck" : "site:\(change.remoteAddress ?? "local")")
        if !change.dryRun { changes.append(change) }
        return site
    }
    func probe(_ service: ServiceID) async throws -> ServiceMoveProbe { try call("probe"); return probeAnswer }
}

private final class Rig: @unchecked Sendable {
    let tape = Tape()
    let source: FakeMachine
    let target: FakeMachine
    let front: FakeMachine
    let events = Tape()
    let records = Tape()

    init(frontIsSource: Bool = false) {
        source = FakeMachine("source", tape: tape, has: true)
        target = FakeMachine("target", tape: tape)
        front = frontIsSource ? source : FakeMachine("front", tape: tape)
    }

    func plan(sourceAddress: String? = "10.0.0.2", targetAddress: String? = "10.0.0.3") -> ServiceMovePlan {
        ServiceMovePlan(
            service: .vaultwarden, target: ServiceMoveEndpoint(host: "10.0.0.3", port: 22, user: "admin"),
            sourceEntryAddress: sourceAddress, targetEntryAddress: targetAddress,
            localPort: 8222, localHTTPS: false, overwriteForwardedFor: false,
            installContext: AgentInstallContext(domain: "example.com"))
    }

    func runner(_ plan: ServiceMovePlan, step: ServiceMoveStep = .check) -> ServiceMoveRunner {
        var record = ServiceMoveRecord(deployment: UUID(), service: .vaultwarden, source: UUID(), target: UUID(),
                                       transferID: "0123456789abcdef0123456789abcdef")
        record.step = step
        if step > .install { record.installedOnTarget = true }
        let steps = events, saved = records
        return ServiceMoveRunner(
            plan: plan, record: record, source: source, target: target, front: front,
            onRecord: { saved.add("\($0.step)") },
            onEvent: { event in
                if case .step(let step) = event { steps.add("\(step)") }
                if case .undoing = event { steps.add("undoing") }
            })
    }
}

final class ServiceMoveRunnerTests: XCTestCase {
    func testAMoveRunsEveryStageInOrderAndLeavesNothingBehind() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        try await rig.runner(rig.plan()).run()
        XCTAssertEqual(rig.events.all, ["check", "install", "backup", "stop", "send", "restore",
                                        "switchEntry", "verify", "finish"])
        let calls = rig.tape.all
        func index(_ call: String) -> Int { calls.firstIndex(of: call) ?? -1 }
        XCTAssertLessThan(index("source.has"), index("target.install"))
        XCTAssertLessThan(index("target.install"), index("source.backup"))
        XCTAssertLessThan(index("source.backup"), index("source.stop"))
        XCTAssertLessThan(index("source.stop"), index("source.prepareSend"))
        XCTAssertLessThan(index("target.authorize:LINE"), index("source.send:/b/a.tar.gz->10.0.0.3:ssh-ed25519 HOST"))
        XCTAssertLessThan(index("target.revoke"), index("target.accept:abc:520"))
        XCTAssertLessThan(index("target.accept:abc:520"), index("target.restore:/new/a.tar.gz"))
        XCTAssertLessThan(index("target.restore:/new/a.tar.gz"), index("front.site:10.0.0.3"))
        XCTAssertLessThan(index("front.site:10.0.0.3"), index("front.probe"))
        XCTAssertTrue(calls.contains("target.prepareReceive:ssh-ed25519 KEY:500"))
        XCTAssertTrue(calls.contains("source.discard") && calls.contains("target.discard"))
        XCTAssertTrue(calls.contains("target.deleteBackup:/new/a.tar.gz"))
        XCTAssertFalse(calls.contains("source.start") || calls.contains("target.removeCopy"))
    }

    func testBringingTheServiceOntoTheFrontPointsTheSiteBackAtItself() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        try await rig.runner(rig.plan(targetAddress: nil)).run()
        XCTAssertEqual(rig.front.changes.map(\.remoteAddress), [nil])
    }

    func testTheFrontBeingTheOldMachineExpectsALocalSiteAndSendsItAway() async throws {
        let rig = Rig(frontIsSource: true)
        rig.source.site = .local
        try await rig.runner(rig.plan(sourceAddress: nil)).run()
        XCTAssertEqual(rig.source.changes.map(\.remoteAddress), ["10.0.0.3"])
    }

    func testAnythingWrongBeforeTheOldMachineIsStoppedTouchesNothingThere() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        rig.source.failing = ["backup"]
        do {
            try await rig.runner(rig.plan()).run()
            XCTFail("the backup failed")
        } catch let failure as ServiceMoveFailure {
            XCTAssertEqual(failure.step, .backup)
            XCTAssertFalse(failure.undone.sourceStarted)
            XCTAssertTrue(failure.undone.targetCopyRemoved, "the fresh install goes again")
            XCTAssertEqual(failure.undone.problems, [])
        }
        XCTAssertFalse(rig.tape.all.contains("source.stop") || rig.tape.all.contains("source.start"))
        XCTAssertTrue(rig.tape.all.contains("target.removeCopy"))
    }

    func testAFailedCopyRevokesTheKeyStartsTheOldCopyAndRemovesTheNewOne() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        rig.source.failing = ["send:/b/a.tar.gz->10.0.0.3:ssh-ed25519 HOST"]
        do {
            try await rig.runner(rig.plan()).run()
            XCTFail("the copy failed")
        } catch let failure as ServiceMoveFailure {
            XCTAssertEqual(failure.step, .send)
            XCTAssertTrue(failure.undone.sourceStarted && failure.undone.targetCopyRemoved)
            XCTAssertFalse(failure.undone.entryRestored, "the site was never switched")
        }
        let calls = rig.tape.all
        XCTAssertTrue(calls.filter { $0 == "target.revoke" }.count >= 1)
        XCTAssertTrue(calls.contains("source.start") && calls.contains("target.removeCopy"))
        XCTAssertFalse(calls.contains { $0.hasPrefix("front.site:") })
    }

    func testASiteThatDoesNotAnswerIsPointedBackAndTheOldCopyStartedAgain() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        rig.front.probeAnswer = ServiceMoveProbe(answered: false, unavailable: false, status: 502, detail: "bad gateway")
        do {
            try await rig.runner(rig.plan()).run()
            XCTFail("the site did not answer")
        } catch let failure as ServiceMoveFailure {
            XCTAssertEqual(failure.step, .verify)
            XCTAssertEqual(failure.underlying as? ServiceMoveProblem, .notAnswering(status: 502, detail: "bad gateway"))
            XCTAssertTrue(failure.undone.entryRestored && failure.undone.sourceStarted && failure.undone.targetCopyRemoved)
        }
        XCTAssertEqual(rig.front.changes.map(\.remoteAddress), ["10.0.0.3", "10.0.0.2"])
        let calls = rig.tape.all
        let back = calls.lastIndex(of: "front.site:10.0.0.2") ?? -1
        XCTAssertLessThan(back, calls.firstIndex(of: "source.start") ?? -1)
    }

    func testAnUndoThatCannotFinishNamesWhatItCouldNotDo() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        rig.target.failing = ["restore:/new/a.tar.gz", "removeCopy"]
        rig.source.failing = ["start"]
        do {
            try await rig.runner(rig.plan()).run()
            XCTFail("the restore failed")
        } catch let failure as ServiceMoveFailure {
            XCTAssertEqual(failure.step, .restore)
            XCTAssertFalse(failure.undone.sourceStarted || failure.undone.targetCopyRemoved)
            XCTAssertEqual(failure.undone.problems.count, 2)
            XCTAssertTrue(failure.undone.problems.contains { $0.contains("starting the old copy") })
        }
    }

    func testTheChecksRefuseBeforeAnythingIsChanged() async throws {
        let cases: [(String, (Rig) -> Void, ServiceMoveProblem)] = [
            ("not on the old machine", { $0.source.has = false }, .notOnSource),
            ("already on the new one", { $0.target.has = true }, .alreadyOnTarget),
            ("no site", { $0.front.site = .missing }, .noSiteOnFront),
            ("the front still serves it itself", { $0.front.site = .local }, .frontDisagrees("local")),
        ]
        for (name, arrange, expected) in cases {
            let rig = Rig()
            rig.front.site = .remote("10.0.0.2")
            arrange(rig)
            do {
                try await rig.runner(rig.plan()).run()
                XCTFail(name)
            } catch let failure as ServiceMoveFailure {
                XCTAssertEqual(failure.underlying as? ServiceMoveProblem, expected, name)
                XCTAssertEqual(failure.step, .check)
                XCTAssertFalse(rig.tape.all.contains("target.install"), name)
                XCTAssertFalse(failure.undone.targetCopyRemoved || failure.undone.sourceStarted, name)
            }
        }
    }

    func testASiteThatCannotBeCheckedDoesNotUndoAMoveThatWorked() async throws {
        let rig = Rig()
        rig.front.site = .remote("10.0.0.2")
        rig.front.probeAnswer = ServiceMoveProbe(answered: false, unavailable: true, status: 0, detail: "no curl")
        try await rig.runner(rig.plan()).run()
        XCTAssertFalse(rig.tape.all.contains("source.start"))
    }

    func testAResumedMoveSkipsWhatAlreadyHappened() async throws {
        let rig = Rig()
        var record = ServiceMoveRecord(deployment: UUID(), service: .vaultwarden, source: UUID(), target: UUID(),
                                       transferID: "0123456789abcdef0123456789abcdef")
        record.step = .restore
        record.installedOnTarget = true
        record.sourceStopped = true
        record.archiveName = "a.tar.gz"
        record.sha256 = "abc"
        record.sentBytes = 520
        let runner = ServiceMoveRunner(plan: rig.plan(), record: record, source: rig.source, target: rig.target,
                                       front: rig.front, onRecord: { _ in }, onEvent: { _ in })
        try await runner.run()
        XCTAssertEqual(rig.tape.all.first, "target.accept:abc:520")
        XCTAssertFalse(rig.tape.all.contains("target.install") || rig.tape.all.contains("source.stop"))
    }

    func testUndoAloneBringsTheOldCopyBackWhenTheEntryWasSwitched() async throws {
        let rig = Rig()
        var record = ServiceMoveRecord(deployment: UUID(), service: .vaultwarden, source: UUID(), target: UUID(),
                                       transferID: "0123456789abcdef0123456789abcdef")
        record.installedOnTarget = true
        record.sourceStopped = true
        record.switchedEntry = true
        let runner = ServiceMoveRunner(plan: rig.plan(), record: record, source: rig.source, target: rig.target,
                                       front: rig.front, onRecord: { _ in }, onEvent: { _ in })
        let undone = await runner.undo()
        XCTAssertTrue(undone.entryRestored && undone.sourceStarted && undone.targetCopyRemoved)
        XCTAssertEqual(rig.front.changes.map(\.remoteAddress), ["10.0.0.2"])
    }
}
