import SwiftUI
import VPNTunnel
import XCTest
@testable import gryonixNexus

final class ServerMetricsWidgetTests: XCTestCase {
    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func codeWithoutComments(_ relative: String) throws -> String {
        let text = try String(contentsOf: appleRoot.appendingPathComponent(relative),
                              encoding: .utf8)
        let code = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.isEmpty, "\(relative) was not read")
        return code
    }

    // MARK: - Numbers

    func testAnUnmeasuredReadingIsADashRatherThanZero() {
        XCTAssertEqual(ServerMetricsPresentation.percent(nil), "—")
        XCTAssertEqual(ServerMetricsPresentation.percent(0), "0%")
        XCTAssertEqual(ServerMetricsPresentation.percent(61.5), "62%")
    }

    func testTheAgeIsSaidInTheFewestWordsThatAreStillTrue() {
        XCTAssertEqual(ServerMetricsPresentation.age(5), "Now")
        XCTAssertEqual(ServerMetricsPresentation.age(59), "Now")
        XCTAssertEqual(ServerMetricsPresentation.age(60 * 5), "5 min ago")
        XCTAssertEqual(ServerMetricsPresentation.age(3_600 * 3), "3 h ago")
        XCTAssertEqual(ServerMetricsPresentation.age(86_400 * 2), "2 d ago")
    }

    func testTheLoadBandsAreThreeAndDistinct() {
        let colours = [10.0, 80.0, 97.0].map(ServerMetricsPresentation.tint)
        XCTAssertEqual(Set(colours.map(String.init(describing:))).count, 3)
        XCTAssertEqual(String(describing: ServerMetricsPresentation.tint(nil)),
                       String(describing: Color.secondary),
                       "an unmeasured reading must not be painted as though it were fine")
    }

    // MARK: - What the app is not allowed to publish

    func testTheDemoFleetIsNotPublishedToWidgets() throws {
        let code = try codeWithoutComments("App/Features/Dashboard/DashboardViewModel.swift")
        XCTAssertTrue(code.contains("!DemoHostMetrics.covers(deployment)"),
                      "invented readings can reach the home screen")
    }

    func testOnlyTheServicesMachineIsPublished() throws {
        let code = try codeWithoutComments("App/Features/Dashboard/DashboardViewModel.swift")
        XCTAssertTrue(code.contains("host == deployment.servicesHost"),
                      "any node's reading can overwrite the one the widget shows")
    }

    func testThePlaceholderLooksLikeAWorkingWidget() {
        let servers = FleetSnapshot.placeholder.servers
        XCTAssertFalse(servers.isEmpty)
        let withReadings = servers.compactMap(\.metrics)
        XCTAssertFalse(withReadings.isEmpty, "the preview has no load to draw")
        XCTAssertTrue(withReadings.contains { ($0.cpuPercent ?? 0) > 0 },
                      "the preview draws an idle machine, which looks like a broken widget")
        XCTAssertTrue(withReadings.allSatisfy { ($0.memoryPercent ?? 0) > 0 },
                      "the preview's memory bars are empty")
    }
}
