import XCTest
import ServiceCatalog
@testable import ServerControl

/// The update wrapper's output, parsed
final class ServiceUpdateOperationsTests: XCTestCase {
    private func statuses(_ output: String) -> [ServiceID: ServiceUpdateStatus] {
        Dictionary(uniqueKeysWithValues: ServiceUpdateOperations.parseCheck(output)
            .map { ($0.service, $0.status) })
    }

    func testAServiceWithNothingToDoReadsAsCurrent() {
        let parsed = statuses("GRYONIXNEXUS_UPDATE_CURRENT jellyfin")
        XCTAssertEqual(parsed[.jellyfin], .current)
    }

    func testEveryMovedImageIsCarriedThroughByName() {
        let parsed = statuses("""
        GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud nextcloud:apache
        GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud mariadb:11
        """)
        XCTAssertEqual(parsed[.nextcloud],
                       .available(images: ["nextcloud:apache", "mariadb:11"]))
    }

    func testAnUnreachableRegistryIsNotCurrent() {
        let parsed = statuses("GRYONIXNEXUS_UPDATE_UNKNOWN immich registry_unreachable")
        XCTAssertEqual(parsed[.immich], .unknown)
        XCTAssertNotEqual(parsed[.immich], .current)
    }

    func testOneMovedImageOutweighsTheRestOfTheStackBeingCurrent() {
        let parsed = statuses("""
        GRYONIXNEXUS_UPDATE_CURRENT seafile
        GRYONIXNEXUS_UPDATE_AVAILABLE seafile redis:7-alpine
        """)
        XCTAssertEqual(parsed[.seafile], .available(images: ["redis:7-alpine"]))
    }

    func testAnIdThisBuildDoesNotKnowIsStillReported() {
        let reports = ServiceUpdateOperations.parseCheck(
            "GRYONIXNEXUS_UPDATE_AVAILABLE some-future-service ghcr.io/x/y:1")
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].service.rawValue, "some-future-service")
    }

    func testProseBetweenTheMarkersIsIgnored() {
        let parsed = statuses("""
        Checking jellyfin…
        GRYONIXNEXUS_UPDATE_CURRENT jellyfin
        Checked 1 service in 2s.
        GRYONIXNEXUS_UPDATE_CTL_DONE
        """)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[.jellyfin], .current)
    }

    func testATruncatedMarkerIsNotAStatus() {
        XCTAssertTrue(ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_CURRENT").isEmpty)
        XCTAssertTrue(ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud")
            .allSatisfy { $0.status == .unknown })
    }

    // MARK: Schedule

    func testAnAbsentConfigReadsAsOff() {
        let settings = ServiceUpdateOperations.parseSchedule("")
        XCTAssertFalse(settings.isOn)
        XCTAssertTrue(settings.services.isEmpty)
    }

    func testTheStoredScheduleAndServiceListAreRead() {
        let settings = ServiceUpdateOperations.parseSchedule("""
        SCHEDULE=every:1d@03:30
        SERVICES="jellyfin nextcloud"
        """)
        XCTAssertTrue(settings.isOn)
        XCTAssertEqual(settings.services, ["jellyfin", "nextcloud"])
    }

    func testAnUnparsableScheduleReadsAsOff() {
        XCTAssertFalse(ServiceUpdateOperations.parseSchedule("SCHEDULE=every-other-tuesday").isOn)
    }

    // MARK: Status

    func testTheLiveStatusFileSampleIsReadInFullDetail() {
        let log = ServiceUpdateOperations.parseStatus("""
        last-run 2026-08-07T19:44:21Z
        GRYONIXNEXUS_UPDATE_DONE jellyfin
        GRYONIXNEXUS_UPDATE_ROLLED_BACK jellyfin a container is still starting
        GRYONIXNEXUS_UPDATE_FAILED adguard-home the backup was refused
        """)
        XCTAssertEqual(log.lastRun, ISO8601DateFormatter().date(from: "2026-08-07T19:44:21Z"))
        XCTAssertEqual(log.records, [
            ServiceUpdateRunRecord(service: .jellyfin, outcome: .updated),
            ServiceUpdateRunRecord(service: .jellyfin,
                                    outcome: .rolledBack(reason: "a container is still starting")),
            ServiceUpdateRunRecord(service: ServiceID(rawValue: "adguard-home"),
                                    outcome: .failed(reason: "the backup was refused")),
        ])
    }

    func testAManualRunWithNoLastRunLineStillYieldsItsRecords() {
        let log = ServiceUpdateOperations.parseStatus("GRYONIXNEXUS_UPDATE_DONE nextcloud")
        XCTAssertNil(log.lastRun)
        XCTAssertEqual(log.records, [ServiceUpdateRunRecord(service: .nextcloud, outcome: .updated)])
    }

    func testAnEmptyFileReadsAsAnEmptyLog() {
        XCTAssertTrue(ServiceUpdateOperations.parseStatus("").isEmpty)
    }

    func testAGarbageLineBetweenMarkersIsIgnored() {
        let log = ServiceUpdateOperations.parseStatus("""
        GRYONIXNEXUS_UPDATE_DONE jellyfin
        pulling registry.example/jellyfin:latest…
        GRYONIXNEXUS_UPDATE_DONE nextcloud
        """)
        XCTAssertEqual(log.records, [
            ServiceUpdateRunRecord(service: .jellyfin, outcome: .updated),
            ServiceUpdateRunRecord(service: .nextcloud, outcome: .updated),
        ])
    }

    func testAReasonWithSeveralWordsIsKeptWhole() {
        let log = ServiceUpdateOperations.parseStatus(
            "GRYONIXNEXUS_UPDATE_ROLLED_BACK immich a container is still starting after the deadline")
        XCTAssertEqual(log.records, [
            ServiceUpdateRunRecord(service: .immich,
                                    outcome: .rolledBack(reason:
                                        "a container is still starting after the deadline")),
        ])
    }

    func testAnUnknownServiceIdSurvivesParsing() {
        let log = ServiceUpdateOperations.parseStatus(
            "GRYONIXNEXUS_UPDATE_DONE some-future-service")
        XCTAssertEqual(log.records.map(\.service.rawValue), ["some-future-service"])
    }

    func testAMalformedTimestampStillLeavesTheRecordsReadable() {
        let log = ServiceUpdateOperations.parseStatus("""
        last-run not-a-date
        GRYONIXNEXUS_UPDATE_DONE jellyfin
        """)
        XCTAssertNil(log.lastRun)
        XCTAssertEqual(log.records, [ServiceUpdateRunRecord(service: .jellyfin, outcome: .updated)])
    }
}
