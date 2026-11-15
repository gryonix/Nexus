import ServerControl
import XCTest

@testable import gryonixNexus

final class ServerGroupOrderTests: XCTestCase {
    private func server(_ name: String, tags: [String]) -> Deployment {
        var deployment = Deployment(name: name, topology: .singleHost, domain: "\(name).example",
                                    entry: HostEndpoint(host: "203.0.113.9", user: "root"))
        deployment.tags = tags
        return deployment
    }

    private func transfer(_ deployment: Deployment) -> DeploymentTransfer {
        DeploymentTransfer(deployment: deployment, wireGuardSeeds: [:], hostKeyPins: [:], reports: [])
    }

    // MARK: - Order

    func testGroupsWithoutAPlaceKeepTheirNameOrder() {
        XCTAssertEqual(ServerGroups.ordered(["Work", "Home", "Lab"], by: []), ["Home", "Lab", "Work"])
    }

    func testPlacedGroupsComeFirstInTheirPlaceOrder() {
        XCTAssertEqual(ServerGroups.ordered(["Work", "Home", "Lab"], by: ["Work", "Lab"]),
                       ["Work", "Lab", "Home"])
    }

    func testMovingRightSwapsWithTheNeighbour() {
        let order = ServerGroups.moving("Home", by: 1, among: ["Home", "Lab", "Work"], stored: [])
        XCTAssertEqual(order, ["Lab", "Home", "Work"])
    }

    func testTheEdgesDoNotMove() {
        XCTAssertNil(ServerGroups.moving("Home", by: -1, among: ["Home", "Lab"], stored: []))
        XCTAssertNil(ServerGroups.moving("Lab", by: 1, among: ["Home", "Lab"], stored: []))
    }

    func testAMoveKeepsThePlacesOfGroupsNotShown() {
        let order = ServerGroups.moving("Lab", by: -1, among: ["Home", "Lab"], stored: ["Old", "Home", "Lab"])
        XCTAssertEqual(order, ["Lab", "Home", "Old"])
    }

    func testRenameAndDeleteFollowTheGroup() {
        XCTAssertEqual(ServerGroups.renaming("lab", to: "Garage", in: ["Home", "Lab"]), ["Home", "Garage"])
        XCTAssertEqual(ServerGroups.removing("HOME", from: ["Home", "Lab"]), ["Lab"])
    }

    func testImportedGroupsJoinAtTheEnd() {
        XCTAssertEqual(ServerGroups.adopting(["lab", "Office"], into: ["Home", "Lab"]),
                       ["Home", "Lab", "Office"])
    }

    func testTheStoredTextRoundTrips() {
        let order = ["Home", "Lab two", "Work"]
        XCTAssertEqual(ServerGroups.parse(ServerGroups.format(order)), order)
    }

    // MARK: - The group file

    func testAGroupFileKeepsOnlyItsOwnGroups() throws {
        let both = server("mail", tags: ["Home", "Work"])
        let bundle = ServerGroupBundle.make(groups: ["Home"], transfers: [transfer(both)])
        XCTAssertEqual(bundle.servers.first?.deployment.tags, ["Home"])
    }

    func testAGroupFileRoundTripsAndIsToldApartFromAServer() throws {
        let deployment = server("cloud", tags: ["Lab"])
        let data = try ServerGroupBundle.make(groups: ["Lab", "Home"], transfers: [transfer(deployment)]).encoded()
        XCTAssertTrue(ServerGroupBundle.isBundle(data))
        let decoded = try ServerGroupBundle.decode(data)
        XCTAssertEqual(decoded.groups, ["Lab", "Home"])
        XCTAssertEqual(decoded.servers.map(\.deployment.id), [deployment.id])

        let single = try DeploymentTransferService.encode(transfer(deployment))
        XCTAssertFalse(ServerGroupBundle.isBundle(single))
    }

    func testAFileFromANewerAppIsRefused() throws {
        var bundle = ServerGroupBundle(groups: ["Lab"], servers: [])
        bundle.version = ServerGroupBundle.currentVersion + 1
        XCTAssertThrowsError(try ServerGroupBundle.decode(bundle.encoded()))
    }

    func testMembersOfSeveralGroupsAreListedOnce() {
        let shared = server("mail", tags: ["Home", "Work"])
        let other = server("vpn", tags: ["Lab"])
        let found = ServerGroups.members(ofAny: ["home", "Work"], in: [shared, other])
        XCTAssertEqual(found.map(\.id), [shared.id])
    }
}
