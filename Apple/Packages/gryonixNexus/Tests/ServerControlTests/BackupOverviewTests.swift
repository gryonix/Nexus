import XCTest
@testable import ServerControl

final class BackupOverviewTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    private func row(_ server: UUID, _ service: String, _ name: String, bytes: Int64? = nil,
                     at seconds: Double? = nil, drive: String? = nil,
                     directory: Bool = false) -> FleetBackup {
        FleetBackup(serverID: server, serverName: server == first ? "one" : "two",
                    serviceID: service, serviceName: service,
                    entry: BackupEntry(name: name, sizeText: "", dateText: "", isDirectory: directory,
                                       drive: drive, sizeBytes: bytes,
                                       modifiedAt: seconds.map { Date(timeIntervalSince1970: $0) }))
    }

    func testNewestComesFirstAndUndatedStayLastInOrder() {
        let rows = [row(first, "a", "old", at: 10), row(first, "a", "none1"),
                    row(second, "b", "new", at: 30), row(first, "a", "none2")]
        XCTAssertEqual(BackupOverview.sorted(rows).map(\.entry.name), ["new", "old", "none1", "none2"])
    }

    func testFilterNarrowsByServiceAndPlace() {
        let rows = [row(first, "a", "x"), row(first, "b", "y", drive: "usb"), row(second, "a", "z")]
        XCTAssertEqual(BackupOverview.filtered(rows, by: BackupFilter(serviceID: "a")).count, 2)
        XCTAssertEqual(BackupOverview.filtered(rows, by: BackupFilter(place: .drives)).map(\.entry.name), ["y"])
        XCTAssertEqual(BackupOverview.filtered(rows, by: BackupFilter(place: .server)).count, 2)
    }

    func testAPlaceAdmitsServerCopiesDriveCopiesOrBoth() {
        let onServer = BackupEntry(name: "a", sizeText: "", dateText: "")
        let onDrive = BackupEntry(name: "b", sizeText: "", dateText: "", drive: "usb")
        XCTAssertTrue(BackupFilter.Place.any.admits(onServer) && BackupFilter.Place.any.admits(onDrive))
        XCTAssertTrue(BackupFilter.Place.server.admits(onServer))
        XCTAssertFalse(BackupFilter.Place.server.admits(onDrive))
        XCTAssertTrue(BackupFilter.Place.drives.admits(onDrive))
        XCTAssertFalse(BackupFilter.Place.drives.admits(onServer))
    }

    func testTotalsCountSizesDrivesAndTheNewest() {
        let rows = [row(first, "a", "x", bytes: 100, at: 5), row(first, "a", "y", bytes: 50, at: 9, drive: "usb"),
                    row(second, "a", "z"), row(second, "a", "dir", directory: true)]
        let totals = BackupOverview.totals(rows)
        XCTAssertEqual(totals.count, 4)
        XCTAssertEqual(totals.bytes, 150)
        XCTAssertEqual(totals.onDrives, 1)
        XCTAssertEqual(totals.unsized, 1)
        XCTAssertEqual(totals.newest, Date(timeIntervalSince1970: 9))
    }

    func testAListedFileCarriesItsSize() {
        let line = "-rw------- 1 root root 3.0M Oct  9 03:00 /opt/backups/x/a.tar.gz"
        XCTAssertEqual(BackupListParser.parse(line).first?.sizeBytes, 3 << 20)
    }
}

final class BackupListDateTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    func testATimeMeansThisYearUnlessThatIsInTheFuture() {
        let now = calendar().date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        let recent = BackupListParser.approximateDate(["Oct", "9", "03:00"], now: now)!
        XCTAssertEqual(calendar().component(.year, from: recent), 2026)
        let late = BackupListParser.approximateDate(["Dec", "30", "03:00"], now: now)!
        XCTAssertEqual(calendar().component(.year, from: late), 2025)
    }

    func testAYearIsTakenAsPrinted() {
        let date = BackupListParser.approximateDate(["Jan", "5", "2024"])!
        XCTAssertEqual(calendar().component(.year, from: date), 2024)
        XCTAssertNil(BackupListParser.approximateDate(["Foo", "5", "2024"]))
    }
}
