import Foundation
@testable import ServerControl
import XCTest

final class DiskHistoryTests: XCTestCase {
    private let text = "120,/srv/data,300,1000\n100,/,50,100\nbroken\n100,/srv/data,100,1000\n120,/,60,100\n130,,1,2\n"

    func testRowsParseInTimeOrderAndBadOnesAreSkipped() {
        let points = DiskHistory.parse(text)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(DiskHistory.mounts(points), ["/", "/srv/data"])
    }

    func testAverageTakesTheMeanPercentAtEachMoment() {
        let lines = DiskHistory.lines(DiskHistory.parse(text), choice: .average)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].values.map(\.value), [30, 45])
    }

    func testEachDiskIsItsOwnLineAndOneDiskIsOnlyThat() {
        let points = DiskHistory.parse(text)
        let each = DiskHistory.lines(points, choice: .each)
        XCTAssertEqual(each.map(\.name), ["/", "/srv/data"])
        XCTAssertEqual(each[1].values.map(\.value), [10, 30])
        XCTAssertEqual(DiskHistory.lines(points, choice: .one("/"))[0].values.map(\.value), [50, 60])
    }

    func testTheCommandReadsTheDisksFileOfTheBucket() {
        XCTAssertEqual(CommandCatalog.diskHistory(bucket: .oneHour),
                       "cat /var/lib/gryonixnexus/metrics/disks-1h.csv 2>/dev/null; true")
    }
}
