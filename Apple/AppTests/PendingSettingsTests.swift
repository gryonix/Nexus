import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// What waits in the bar, and what a refusal advises
@MainActor
final class PendingSettingsTests: XCTestCase {
    func testHomeOnlySwitchesWaitOnlyWhenTheyDiffer() {
        var draft = HomeOnlyDraft()
        XCTAssertFalse(draft.waits(homeOnly: false, noVPN: false))
        draft.homeOnly = false
        XCTAssertFalse(draft.waits(homeOnly: false, noVPN: false), "the same value is no change")
        draft.homeOnly = true
        XCTAssertTrue(draft.waits(homeOnly: false, noVPN: false))
        XCTAssertFalse(draft.waits(homeOnly: true, noVPN: false), "the server already has it")
        draft = HomeOnlyDraft(homeOnly: nil, noVPN: true)
        XCTAssertTrue(draft.waits(homeOnly: true, noVPN: false))
        XCTAssertFalse(draft.waits(homeOnly: true, noVPN: true))
    }

    func testOpenAPISwitchesWaitOnlyWhenTheyDiffer() throws {
        let service = try XCTUnwrap(ServiceRegistry.all.first { !ServiceAPIGroups.groups(for: $0.id).isEmpty })
        let groups = ServiceAPIGroups.groups(for: service.id)
        let first = try XCTUnwrap(groups.first)

        let same = OpenAPIGroupsSection.waiting([first.id: false], among: groups) { _ in false }
        XCTAssertTrue(same.isEmpty)
        let opened = OpenAPIGroupsSection.waiting([first.id: true, "no-such-group": true], among: groups) { _ in false }
        XCTAssertEqual(opened.map { $0.group.id }, [first.id])
        XCTAssertEqual(opened.map { $0.open }, [true])
        XCTAssertTrue(OpenAPIGroupsSection.waiting([:], among: groups) { _ in true }.isEmpty)
    }

    func testHubOutputAndPlayersBecomeCallsOnlyWhereTheyDiffer() {
        var state = AudioHubState()
        state.outputs = AudioHubParser.outputs("""
        [{"id":0,"name":"hdmi","description":"HDMI","volume":0.5,"muted":false,"default":true},
         {"id":1,"name":"usb","description":"USB","volume":0.5,"muted":false,"default":false}]
        """)
        state.services = AudioHubParser.services("""
        [{"name":"mpd.service","scope":"user","running":false,"exists":true,"description":"Music Player Daemon"}]
        """)
        XCTAssertEqual(state.defaultOutput, "hdmi")
        XCTAssertEqual(state.services.map(\.unit), ["mpd.service"])

        var draft = AudioHubDraft()
        draft.output = "hdmi"
        draft.players["mpd.service"] = false
        XCTAssertTrue(draft.calls(against: state).isEmpty, "nothing differs from the hub")

        draft.output = "usb"
        draft.players["mpd.service"] = true
        draft.players["gone.service"] = true
        XCTAssertEqual(draft.calls(against: state),
                       ["/audio/outputs/usb/default", "/services/user/mpd.service/start"])
    }

    func testAContainerGroupTakesTheServicesGivenNameUnlessItHasItsOwn() {
        let suite = "pending-settings-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ServiceOwnNames(local: defaults)
        let server = UUID()
        store.set("Passwords", service: .vaultwarden, server: server.uuidString, sent: true)

        func group(renamed: Bool, serviceID: String?) -> ContainerGroup {
            ContainerGroup(key: "k", isComposeProject: true, displayName: renamed ? "Mine" : "Vaultwarden",
                           derivedName: "Vaultwarden", isRenamed: renamed, serviceID: serviceID,
                           status: .running, containers: [], configFiles: [])
        }
        XCTAssertEqual(store.title(ofGroup: group(renamed: false, serviceID: "vaultwarden"), server: server), "Passwords")
        XCTAssertEqual(store.title(ofGroup: group(renamed: true, serviceID: "vaultwarden"), server: server), "Mine")
        XCTAssertEqual(store.title(ofGroup: group(renamed: false, serviceID: nil), server: server), "Vaultwarden")
        XCTAssertEqual(store.title(ofGroup: group(renamed: false, serviceID: "vaultwarden"), server: UUID()), "Vaultwarden")
    }

    func testTheNewRefusalReasonsHaveAdvice() {
        let reasons = ["host.docker_unavailable", "sites.caddy_refused", "audio.hub_not_answering",
                       "security.ssh_unchanged", "firewall.rules_refused", "move.no_space", "backup.unreadable"]
        for reason in reasons {
            let message = "refused for the test: \(reason)"
            AgentRefusals.shared.remember(AgentRefusal(reason: reason, args: [], message: message))
            let advice = RefusalSolution.advice(for: "Could not do it. \(message)")
            XCTAssertFalse(advice?.isEmpty ?? true, reason)
            XCTAssertFalse(advice?.contains("%@") ?? true, reason)
        }
    }

    func testAReasonWithoutAdviceShowsOnlyTheAgentsText() {
        let message = "refused for the test: move.refused"
        AgentRefusals.shared.remember(AgentRefusal(reason: "move.refused", args: [], message: message))
        XCTAssertNil(RefusalSolution.advice(for: message))
    }

    func testEveryBarHasItsWordsAndNoPlainTick() {
        for text in [PendingChangesText.apply, .save, .schedule, .mods, .speaker, .screen] {
            XCTAssertNotEqual(text.systemImage, "checkmark")
            XCTAssertFalse(text.systemImage.isEmpty)
        }
        XCTAssertNil(PendingChangesText.save.note)
        XCTAssertNotNil(PendingChangesText.speaker.note)
    }
}
