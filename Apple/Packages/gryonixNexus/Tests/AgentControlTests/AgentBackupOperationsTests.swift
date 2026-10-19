import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct MockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }
    var onStream: @Sendable (String, Data) -> AsyncThrowingStream<Data, Error> = { _, _ in
        AsyncThrowingStream { $0.finish() }
    }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        onStream(path, request)
    }
}

private func archive(_ path: String, bytes: Int64, at millis: Int64,
                     directory: Bool = false) -> Gryonixnexusd_V1_BackupArchive {
    var archive = Gryonixnexusd_V1_BackupArchive()
    archive.name = path.split(separator: "/").last.map(String.init) ?? path
    archive.path = path
    archive.sizeBytes = bytes
    archive.modifiedAt = millis
    archive.directory = directory
    return archive
}

private func service(_ id: ServiceID) throws -> any ManagedService {
    try XCTUnwrap(ServiceRegistry.service(id))
}

/// One backup event, framed the way the client decodes it
private func event(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                   text: String = "",
                   archive announced: Gryonixnexusd_V1_BackupArchive? = nil,
                   listing: [Gryonixnexusd_V1_BackupArchive]? = nil) -> Data {
    var event = Gryonixnexusd_V1_BackupEvent()
    event.phase = phase
    event.text = text
    if let announced { event.archive = announced }
    if let listing {
        var list = Gryonixnexusd_V1_BackupList()
        list.archives = listing
        event.backups = list
    }
    return (try? event.serializedBytes()) ?? Data()
}

final class AgentBackupOperationsTests: XCTestCase {
    // MARK: - Routing

    func testOnlyTheWrapperDrivenFlavourGoesThroughTheAgent() {
        XCTAssertEqual(BackupRouting.route(usesAgent: true, agentTransportAvailable: true,
                                           kind: .wrapper), .agent)
        XCTAssertEqual(BackupRouting.route(usesAgent: true, agentTransportAvailable: true,
                                           kind: .encrypted), .ssh)
        XCTAssertEqual(BackupRouting.route(usesAgent: true, agentTransportAvailable: true,
                                           kind: .none), .ssh)
    }

    func testAnAgentlessDeploymentKeepsBackingUpOverSSH() {
        for kind in [ServiceOperations.BackupKind.wrapper, .encrypted, .none] {
            XCTAssertEqual(BackupRouting.route(usesAgent: false, agentTransportAvailable: true,
                                               kind: kind), .ssh)
            XCTAssertEqual(BackupRouting.route(usesAgent: false, agentTransportAvailable: false,
                                               kind: kind), .ssh)
        }
        XCTAssertEqual(BackupRouting.route(usesAgent: true, agentTransportAvailable: false,
                                           kind: .wrapper), .ssh)
    }

    // MARK: - Listing

    func testListingCarriesAbsolutePathsSoDeleteAndRestoreNeedNoBranch() async throws {
        var list = Gryonixnexusd_V1_BackupList()
        list.serviceID = "nextcloud"
        list.directory = "/opt/backups/nextcloud"
        list.archives = [
            archive("/opt/backups/nextcloud/nextcloud-20260806.tar.gz.gpg", bytes: 360_000_000,
                    at: 1_754_400_000_000),
            archive("/opt/backups/nextcloud/mailcow-20260805", bytes: 4096,
                    at: 1_754_300_000_000, directory: true)
        ]
        let payload: Data = try list.serializedBytes()
        let sent = LockedBox<String>()

        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/ListBackups")
                sent.value = try Gryonixnexusd_V1_ListBackupsRequest(serializedBytes: request).serviceID
                return payload
            })))

        let entries = try await backups.listBackups(of: try service(.nextcloud))
        XCTAssertEqual(sent.value, "nextcloud", "the wire carries a catalog id, never a path")
        XCTAssertEqual(entries.first?.name, "/opt/backups/nextcloud/nextcloud-20260806.tar.gz.gpg")
        XCTAssertEqual(entries.first?.displayName, "nextcloud-20260806.tar.gz.gpg")
        XCTAssertFalse(entries.first?.isDirectory ?? true)
        XCTAssertTrue(entries.last?.isDirectory ?? false)
        XCTAssertEqual(entries.last?.sizeText, "—")
        XCTAssertTrue(entries.first?.sizeText.contains("MB") ?? false, "\(entries.first?.sizeText ?? "")")
        XCTAssertFalse(entries.first?.dateText.isEmpty ?? true)
    }

    func testOneCallListsEveryServiceWithoutTheCap() async throws {
        var nextcloud = Gryonixnexusd_V1_BackupList()
        nextcloud.serviceID = "nextcloud"
        nextcloud.archives = (0..<15).map {
            archive("/opt/backups/nextcloud/n-\($0).tar.gz", bytes: 10, at: Int64($0) * 1000)
        }
        var vault = Gryonixnexusd_V1_BackupList()
        vault.serviceID = "vaultwarden"
        var all = Gryonixnexusd_V1_AllBackups()
        all.lists = [nextcloud, vault]
        let payload: Data = try all.serializedBytes()
        let paths = LockedBox<String>()
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                paths.value = path
                return payload
            })))

        let listed = try await backups.listAll()

        XCTAssertEqual(paths.value, "/gryonixnexusd.v1.Backup/ListAllBackups")
        XCTAssertEqual(listed["nextcloud"]?.count, 15)
        XCTAssertEqual(listed["vaultwarden"]?.count, 0)
        XCTAssertEqual(listed["nextcloud"]?.first?.sizeBytes, 10)
    }

    func testTheListingIsCappedTheSameWayTheSSHParserCapsIt() async throws {
        var list = Gryonixnexusd_V1_BackupList()
        list.archives = (0..<25).map {
            archive("/opt/backups/immich/immich-\($0).tar.gz", bytes: 10, at: Int64(25 - $0) * 1000)
        }
        let payload: Data = try list.serializedBytes()
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { _, _ in payload })))
        let entries = try await backups.listBackups(of: try service(.immich))
        XCTAssertEqual(entries.count, BackupListParser.defaultLimit)
        XCTAssertEqual(entries.first?.displayName, "immich-0.tar.gz")
    }

    // MARK: - Estimate

    func testEstimateArrivesAsBytesSoTheAppDecidesWhatTooBigMeans() async throws {
        var estimate = Gryonixnexusd_V1_BackupEstimate()
        estimate.dataBytes = 1_073_741_824
        estimate.freeBytes = 223_338_299_392
        let payload: Data = try estimate.serializedBytes()

        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/EstimateBackup")
                return payload
            })))
        let result = try await backups.estimate(of: try service(.nextcloud))
        XCTAssertEqual(result?.dataBytes, 1_073_741_824)
        XCTAssertEqual(result?.freeBytes, 223_338_299_392)
        XCTAssertEqual(result?.fitsOnDisk, true)
    }

    // MARK: - Running

    func testANilEncryptionChoiceLeavesTheDefaultToTheWrapper() async throws {
        for (choice, expected) in [(Bool?.none, Gryonixnexusd_V1_BackupEncryption.unspecified),
                                   (true, .enabled),
                                   (false, .disabled)] {
            let sent = LockedBox<Gryonixnexusd_V1_RunBackupRequest>()
            let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
                onStream: { path, request in
                    XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/RunBackup")
                    sent.value = try? Gryonixnexusd_V1_RunBackupRequest(serializedBytes: request)
                    return AsyncThrowingStream { $0.finish() }
                })))
            _ = try await backups.backup(try service(.nextcloud), encrypt: choice,
                                         passphrase: nil, onChunk: { _ in })
            XCTAssertEqual(sent.value?.encryption, expected)
        }
    }

    func testThePassphraseTravelsAsARequestFieldNotAsACommandLine() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_RunBackupRequest>()
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, request in
                sent.value = try? Gryonixnexusd_V1_RunBackupRequest(serializedBytes: request)
                return AsyncThrowingStream { $0.finish() }
            })))
        _ = try await backups.backup(try service(.nextcloud), encrypt: true,
                                     passphrase: "correct horse battery staple", onChunk: { _ in })
        XCTAssertEqual(sent.value?.passphrase, "correct horse battery staple")
        XCTAssertEqual(sent.value?.serviceID, "nextcloud")
    }

    func testTheAnnouncedArchiveAndTheStreamedLogBothReachTheCaller() async throws {
        let announced = archive("/opt/backups/nextcloud/nextcloud-20260806.tar.gz", bytes: 4096,
                                at: 1_754_400_000_000)
        let payloads = [
            event(.started),
            event(.progress, text: "dumping the nextcloud database"),
            event(.progress, text: "archiving"),
            event(.completed, archive: announced, listing: [announced])
        ]
        let chunks = LockedBox<[String]>()
        chunks.value = []
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    for payload in payloads { continuation.yield(payload) }
                    continuation.finish()
                }
            })))

        let outcome = try await backups.backup(try service(.nextcloud), encrypt: false,
                                               passphrase: nil,
                                               onChunk: { chunks.value = (chunks.value ?? []) + [$0] })
        XCTAssertEqual(outcome.path, "/opt/backups/nextcloud/nextcloud-20260806.tar.gz")
        XCTAssertEqual(outcome.sizeBytes, 4096)
        XCTAssertEqual(chunks.value?.count, 2, "only the progress lines are streamed")
        XCTAssertTrue(outcome.log.contains("archiving"), outcome.log)
    }

    func testAFailedRunStillDeliversTheBackupDirectoryAsReReadAfterIt() async throws {
        let survivor = archive("/opt/backups/nextcloud/nextcloud-20260805.tar.gz", bytes: 900,
                               at: 1_754_300_000_000)
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(event(.progress, text: "archiving"))
                    continuation.yield(event(.completed, listing: [survivor]))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "the nextcloud database dump failed"))
                }
            })))

        do {
            _ = try await backups.backup(try service(.nextcloud), encrypt: nil,
                                         passphrase: nil, onChunk: { _ in })
            XCTFail("a failed run must throw")
        } catch let error as AgentControlError {
            guard case .backupFailed(let underlying, let listing) = error else {
                return XCTFail("expected backupFailed, got \(error)")
            }
            XCTAssertEqual(underlying, .rpc(code: "internal", message: "the nextcloud database dump failed"))
            XCTAssertEqual(listing.map(\.displayName), ["nextcloud-20260805.tar.gz"])
            XCTAssertEqual(error.errorDescription, "the nextcloud database dump failed")
        }
    }

    func testARunThatFailedLeavingNothingStillReportsThatItLeftNothing() async throws {
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(event(.progress, text: "nextcloud has no data at /opt/nextcloud/data"))
                    continuation.yield(event(.completed, listing: []))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "nextcloud backup failed"))
                }
            })))

        do {
            _ = try await backups.backup(try service(.nextcloud), encrypt: nil,
                                         passphrase: nil, onChunk: { _ in })
            XCTFail("a failed run must throw")
        } catch let error as AgentControlError {
            guard case .backupFailed(let underlying, let listing) = error else {
                return XCTFail("expected backupFailed, got \(error)")
            }
            XCTAssertEqual(underlying, .rpc(code: "internal", message: "nextcloud backup failed"))
            XCTAssertTrue(listing.isEmpty, "\(listing)")
        } catch {
            XCTFail("expected backupFailed, got \(error)")
        }
    }

    func testARefusalBeforeAnythingRanKeepsItsOwnConnectCode() async throws {
        let refusal = AgentError.rpc(code: "failed_precondition",
                                     message: "this server has no backup wrapper")
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in AsyncThrowingStream { $0.finish(throwing: refusal) } })))

        do {
            _ = try await backups.backup(try service(.nextcloud), encrypt: nil,
                                         passphrase: nil, onChunk: { _ in })
            XCTFail("a refused run must throw")
        } catch let error as AgentError {
            XCTAssertEqual(error, refusal)
        } catch {
            XCTFail("expected the agent's own error, got \(error)")
        }
    }

    // MARK: - Delete

    func testDeleteSendsThePathTheListingProduced() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_DeleteBackupRequest>()
        let payload: Data = try Gryonixnexusd_V1_BackupList().serializedBytes()
        let backups = AgentBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/DeleteBackup")
                sent.value = try Gryonixnexusd_V1_DeleteBackupRequest(serializedBytes: request)
                return payload
            })))

        try await backups.deleteBackup(try service(.immich),
                                       path: "/opt/backups/immich/immich-20260806.tar.gz")
        XCTAssertEqual(sent.value?.serviceID, "immich")
        XCTAssertEqual(sent.value?.path, "/opt/backups/immich/immich-20260806.tar.gz")
    }

    // MARK: - Addressing

    func testEveryCatalogServiceIsAddressableByTheAgent() throws {
        for service in ServiceRegistry.all {
            XCTAssertNotNil(AgentServiceMapping.agentID(for: service.id),
                            "\(service.id.rawValue) has no agent id")
        }
        for id in ServiceID.vpnProtocols.union([.vpnPanel]) {
            XCTAssertEqual(AgentServiceMapping.agentID(for: id), "vpn", "\(id.rawValue)")
        }
        XCTAssertNil(AgentServiceMapping.agentID(for: ServiceID(rawValue: "some-future-service")))
    }
}
