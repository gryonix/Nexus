import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct MockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func point(at seconds: Double, cpu: Double?, temperature: Double?) -> Gryonixnexusd_V1_MetricsHistoryPoint {
    var point = Gryonixnexusd_V1_MetricsHistoryPoint()
    point.at = Int64(seconds * 1000)
    if let cpu { point.cpuPercent = cpu }
    point.memUsedBytes = 1_073_741_824
    point.memTotalBytes = 4_294_967_296
    point.diskUsedBytes = 5_368_709_120
    point.diskTotalBytes = 107_374_182_400
    point.load1 = 0.42
    if let temperature { point.temperatureCelsius = temperature }
    return point
}

final class AgentMetricsHistoryTests: XCTestCase {
    // MARK: - Routing

    func testHistoryUsesTheAgentOnlyForTheHostTheAgentRunsOn() {
        // Scenario A / the services host: the agent answers.
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: true,
                                                   host: .home, agentHost: .home), .agent)
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: true,
                                                   host: .vps, agentHost: .home), .ssh)
    }

    func testAWorkerBeyondTheTwoSlotsReadsItsHistoryOverSSH() {
        let third = SSHHostID.node(UUID())
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: true,
                                                   host: third, agentHost: .home), .ssh,
                       "the agent's buckets are the home machine's - answering for another host "
                       + "would draw one machine's chart under another's name")
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: true,
                                                   host: .home, agentHost: .home), .agent)
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: true,
                                                   host: third, agentHost: third), .agent)
    }

    func testAnAgentlessDeploymentKeepsReadingHistoryOverSSH() {
        for host in [SSHHostID.vps, .home] {
            XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: false, agentTransportAvailable: true,
                                                       host: host, agentHost: host), .ssh)
            XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: false, agentTransportAvailable: false,
                                                       host: host, agentHost: host), .ssh)
        }
        XCTAssertEqual(MetricsHistoryRouting.route(usesAgent: true, agentTransportAvailable: false,
                                                   host: .home, agentHost: .home), .ssh)
    }

    // MARK: - The wire

    func testEveryCollectorBucketTravelsByItsOwnName() async throws {
        for bucket in MetricsHistoryBucket.allCases {
            let sent = LockedBox<String>()
            var response = Gryonixnexusd_V1_MetricsHistoryResponse()
            response.bucket = bucket.rawValue
            let payload: Data = try response.serializedBytes()
            let source = AgentMetricsHistory(client: AgentClient(transport: MockTransport(
                onUnary: { path, request in
                    XCTAssertEqual(path, "/gryonixnexusd.v1.Control/MetricsHistory")
                    sent.value = try Gryonixnexusd_V1_MetricsHistoryRequest(serializedBytes: request).bucket
                    return payload
                })))
            _ = try await source.history(bucket: bucket, on: .home)
            XCTAssertEqual(sent.value, bucket.rawValue)
        }
    }

    func testAbsentRatesAndTemperatureStayAbsentInsteadOfBecomingZero() async throws {
        var response = Gryonixnexusd_V1_MetricsHistoryResponse()
        response.bucket = "10s"
        response.points = [
            point(at: 1_754_400_000, cpu: 12.5, temperature: 41.2),
            point(at: 1_754_400_010, cpu: nil, temperature: nil)
        ]
        let payload: Data = try response.serializedBytes()

        let source = AgentMetricsHistory(client: AgentClient(transport: MockTransport(
            onUnary: { _, _ in payload })))
        let points = try await source.history(bucket: .tenSeconds, on: .home)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].cpuPercent, 12.5)
        XCTAssertEqual(points[0].temperatureCelsius, 41.2)
        XCTAssertEqual(points[0].date.timeIntervalSince1970, 1_754_400_000, accuracy: 0.001)
        XCTAssertEqual(points[0].memUsedBytes, 1_073_741_824)
        XCTAssertNil(points[1].cpuPercent)
        XCTAssertNil(points[1].temperatureCelsius)
        XCTAssertNil(points[1].netReceivedPerSecond)
        XCTAssertNil(points[1].diskWrittenPerSecond)
    }

    func testAWindowIsAppliedOnTheServerSoUndrawnRowsAreNotTransferred() async throws {
        let sent = LockedBox<Int64>()
        var response = Gryonixnexusd_V1_MetricsHistoryResponse()
        response.bucket = "1m"
        let payload: Data = try response.serializedBytes()

        let source = AgentMetricsHistory(client: AgentClient(transport: MockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_MetricsHistoryRequest(serializedBytes: request).since
                return payload
            })), gate: nil, window: 3600)
        _ = try await source.history(bucket: .oneMinute, on: .home)

        let expected = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        XCTAssertEqual(Double(sent.value ?? 0), expected, accuracy: 5000)
    }

    func testWithoutAWindowNoLowerBoundIsSentAtAll() async throws {
        let sent = LockedBox<Int64>()
        var response = Gryonixnexusd_V1_MetricsHistoryResponse()
        response.bucket = "1w"
        let payload: Data = try response.serializedBytes()
        let source = AgentMetricsHistory(client: AgentClient(transport: MockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_MetricsHistoryRequest(serializedBytes: request).since
                return payload
            })))
        _ = try await source.history(bucket: .oneWeek, on: .home)
        XCTAssertEqual(sent.value, 0)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
