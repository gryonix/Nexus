import ServerControl
import XCTest

@testable import gryonixNexus

final class ConfiguratorDraftRecoveryTests: XCTestCase {
    func testSavedAnswersSurviveTheRecovery() {
        var saved = ConfiguratorDraft(topology: .singleHost)
        saved.distribution = "ubuntu"
        saved.reverseDNSHostname = "mail.example.test"
        saved.vpsVPNIP = "10.9.0.1"

        var draft = ConfiguratorDraft(topology: .singleHost)
        draft.carryUnrecoverable(from: saved)

        XCTAssertEqual(draft.entryDistribution, .ubuntu)
        XCTAssertEqual(draft.reverseDNSHostname, "mail.example.test")
        XCTAssertEqual(draft.vpsVPNIP, "10.9.0.1")
    }

    func testARecordWithoutNodeDistributionsKeepsTheDraftsOwn() {
        let deployment = Deployment(name: "a", topology: .singleHost, domain: "a.test",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "u"))
        var draft = ConfiguratorDraft(topology: .singleHost)
        draft.distribution = "ubuntu"

        draft.adoptDistributions(of: deployment)

        XCTAssertEqual(draft.entryDistribution, .ubuntu)
    }
}
