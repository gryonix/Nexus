import gryonixNexusCore
import ServerControl
import ServiceCatalog
import XCTest
@testable import gryonixNexus

final class HomeOnlyDNSTests: XCTestCase {
    private struct FakeProvider: DNSPublishingProvider {
        let displayName = "Fake"
        let recorder: Recorder
        func apply(_ records: [DNSRecord], zone: String) async throws {}
        func verifyToken() async throws {}
        func publishReportingOutcomes(_ records: [DNSRecord], zone: String) async throws -> [DNSPublishOutcome] {
            await recorder.add("publish \(records.map(\.name)) \(zone)")
            return records.map { DNSPublishOutcome(record: $0, result: .created) }
        }
        func removeAddressRecords(named names: [String], pointingAt address: String, zone: String) async throws -> [String] {
            await recorder.add("remove \(names) \(address) \(zone)")
            return names
        }
    }

    private actor Recorder {
        var calls: [String] = []
        func add(_ call: String) { calls.append(call) }
    }

    private func vault(removed: Set<ServiceID> = []) -> Deployment {
        Deployment(name: "pair", topology: .singleHost, domain: "example.test",
                   entry: HostEndpoint(host: "203.0.113.40", user: "root"), services: [.vaultwarden],
                   homeOnlyDNSRemoved: removed)
    }

    @MainActor
    func testRemovingCallsTheProviderForTheServiceName() async throws {
        let service = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let recorder = Recorder()
        let outcome = await HomeOnlyDNS.change(.remove, service, in: vault(),
                                               provider: { FakeProvider(recorder: recorder) }, lookup: { _ in [] })
        guard case .done = outcome else { return XCTFail("\(outcome)") }
        let calls = await recorder.calls
        XCTAssertEqual(calls, ["remove [\"vault.example.test\"] 203.0.113.40 example.test"])
    }

    @MainActor
    func testRestoringPublishesTheRecordAgain() async throws {
        let service = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let recorder = Recorder()
        let outcome = await HomeOnlyDNS.change(.restore, service, in: vault(removed: [.vaultwarden]),
                                               provider: { FakeProvider(recorder: recorder) }, lookup: { _ in [] })
        guard case .done = outcome else { return XCTFail("\(outcome)") }
        let calls = await recorder.calls
        XCTAssertEqual(calls, ["publish [\"vault.example.test\"] example.test"])
    }

    @MainActor
    func testWithoutATokenTheUserGetsTheRecordsToChangeByHand() async throws {
        let service = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let outcome = await HomeOnlyDNS.change(.remove, service, in: vault(), provider: { nil }, lookup: { _ in [] })
        guard case .manual(let manual) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(manual.action, .remove)
        XCTAssertEqual(manual.lines, ["vault.example.test A 203.0.113.40"])
    }

    func testARemovedRecordIsNotPublishedAgainBySync() async throws {
        let service = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let (update, notes) = await ServiceDNSPublisher.pending(adding: service, to: vault(removed: [.vaultwarden])) { _ in [] }
        XCTAssertNil(update)
        XCTAssertTrue(notes.isEmpty)
        let lines = await ServiceDNSPublisher.publish(service, for: vault(removed: [.vaultwarden]))
        XCTAssertTrue(lines.isEmpty)
    }
}
