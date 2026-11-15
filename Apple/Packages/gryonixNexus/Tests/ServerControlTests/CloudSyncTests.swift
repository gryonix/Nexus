import Foundation
@testable import ServerControl
import XCTest

final class CloudSyncTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    func testOnlyTheKeyModesCarryKeys() {
        XCTAssertEqual(CloudSyncMode.allCases.filter(\.includesKeys), [.apple, .applePassword])
        XCTAssertEqual(CloudSyncMode.allCases.filter(\.usesPassword), [.applePassword])
        XCTAssertFalse(CloudSyncMode.off.syncs)
    }

    func testTheEnvelopeSurvivesTheRoundTrip() throws {
        let envelope = CloudSyncEnvelope(modifiedAt: later, sealed: true, payload: Data([1, 2, 3]))
        XCTAssertEqual(CloudSyncEnvelope.decode(try envelope.encoded()), envelope)
    }

    func testANewerEnvelopeVersionIsLeftAlone() throws {
        var envelope = CloudSyncEnvelope(modifiedAt: later)
        envelope.version = CloudSyncEnvelope.currentVersion + 1
        XCTAssertNil(CloudSyncEnvelope.decode(try envelope.encoded()))
    }

    func testThePasswordOpensWhatItSealed() throws {
        let (lock, key) = try CloudSyncSeal.lock(password: "correct horse")
        let sealed = try CloudSyncSeal.seal(Data("server".utf8), key: key)
        XCTAssertNotEqual(sealed, Data("server".utf8))
        let again = try CloudSyncSeal.unlock(lock, password: "correct horse")
        XCTAssertEqual(try CloudSyncSeal.open(sealed, key: again), Data("server".utf8))
        XCTAssertTrue(CloudSyncSeal.fits(again, lock))
    }

    func testAWrongPasswordIsRefused() throws {
        let (lock, _) = try CloudSyncSeal.lock(password: "correct horse")
        XCTAssertThrowsError(try CloudSyncSeal.unlock(lock, password: "wrong")) {
            XCTAssertEqual($0 as? TransferSeal.Failure, .wrongPassphrase)
        }
    }

    func testANewDeviceTakesWhatICloudHas() {
        let remote = CloudSyncEnvelope(modifiedAt: later)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: nil, mark: nil), .apply)
    }

    func testALocalServerICloudLacksIsPushed() {
        XCTAssertEqual(CloudSyncPlanner.decide(remote: nil, localHash: "a", mark: nil), .push)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: nil, localHash: nil, mark: nil), .nothing)
    }

    func testAnUnchangedServerStaysQuiet() {
        let remote = CloudSyncEnvelope(modifiedAt: earlier)
        let mark = CloudSyncMark(hash: "a", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "a", mark: mark), .nothing)
    }

    func testALocalEditIsPushed() {
        let remote = CloudSyncEnvelope(modifiedAt: earlier)
        let mark = CloudSyncMark(hash: "a", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "b", mark: mark), .push)
    }

    func testANewerRemoteEditWins() {
        let remote = CloudSyncEnvelope(modifiedAt: later)
        let mark = CloudSyncMark(hash: "a", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "b", mark: mark), .apply)
    }

    func testARemoteDeletionRemovesTheLocalCopy() {
        let remote = CloudSyncEnvelope(modifiedAt: later, deleted: true)
        let mark = CloudSyncMark(hash: "a", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "a", mark: mark), .delete)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: nil, mark: nil), .nothing)
    }

    func testALocalDeletionStaysOnThisDevice() {
        let remote = CloudSyncEnvelope(modifiedAt: earlier)
        let mark = CloudSyncMark(hash: "a", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: nil, mark: mark), .dismiss)
    }

    func testADismissedServerIsNotBroughtBack() {
        let remote = CloudSyncEnvelope(modifiedAt: Date())
        let mark = CloudSyncMark(hash: "", at: earlier, dismissed: true)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: nil, mark: mark), .nothing)
    }

    func testADismissedServerAddedBackIsPushed() {
        let remote = CloudSyncEnvelope(modifiedAt: earlier)
        let mark = CloudSyncMark(hash: "a", at: earlier, dismissed: true)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "a", mark: mark), .push)
    }

    func testAnOlderMarkWithoutTheFlagStillDecodes() throws {
        let old = Data(#"{"hash":"a","at":0}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(CloudSyncMark.self, from: old).dismissed)
    }

    func testAServerAddedBackAfterADeletionIsPushed() {
        let remote = CloudSyncEnvelope(modifiedAt: earlier, deleted: true)
        let mark = CloudSyncMark(hash: "", at: earlier)
        XCTAssertEqual(CloudSyncPlanner.decide(remote: remote, localHash: "a", mark: mark), .push)
    }

    func testTheHashFollowsTheContent() {
        XCTAssertEqual(CloudSyncPlanner.hash(Data("a".utf8)), CloudSyncPlanner.hash(Data("a".utf8)))
        XCTAssertNotEqual(CloudSyncPlanner.hash(Data("a".utf8)), CloudSyncPlanner.hash(Data("b".utf8)))
    }

    func testAnEnvelopesOwnRoundTripIsNotANewerEdit() throws {
        let pushed = Date()
        let mark = CloudSyncMark(hash: "h", at: pushed)
        for nudge in [0.0, 0.0000004, 0.0004] {
            let remote = CloudSyncEnvelope(modifiedAt: pushed.addingTimeInterval(nudge), payload: Data("x".utf8))
            let decoded = try XCTUnwrap(CloudSyncEnvelope.decode(remote.encoded()))
            XCTAssertEqual(CloudSyncPlanner.decide(remote: decoded, localHash: nil, mark: mark), .dismiss,
                           "a server deleted here must not come back from its own copy")
        }
    }
}
