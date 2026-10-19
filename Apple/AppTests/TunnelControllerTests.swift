import ServiceCatalog
import VPNProfile
import XCTest
import VPNTunnel
@testable import gryonixNexus

/// What the controller WRITES DOWN when the engine moves
@MainActor
final class TunnelControllerTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var engine: FakeTunnelEngine!
    private var secrets: InMemoryTunnelSecretStore!
    private var profileStore: TunnelProfileStore!
    private var sessionLog: TunnelSessionLog!
    private var snapshots: FleetSnapshotStore!
    private var activity: RecordingTunnelActivity!
    private var activitySettings: LiveActivitySettings!
    private var wasEverActive: Any?
    private static let everActiveKey = "licenseWasActive"

    private let configuration = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32
    DNS = 10.9.0.1
    MTU = 1280

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    """

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "TunnelControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        engine = FakeTunnelEngine()
        secrets = InMemoryTunnelSecretStore()
        profileStore = TunnelProfileStore(fileURL: directory.appendingPathComponent("profiles.json"),
                                          defaults: defaults)
        sessionLog = TunnelSessionLog(fileURL: directory.appendingPathComponent("sessions.json"))
        snapshots = FleetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        activity = RecordingTunnelActivity()
        activitySettings = LiveActivitySettings(defaults: defaults)
        wasEverActive = UserDefaults.standard.object(forKey: Self.everActiveKey)
        LicenseStore.shared.setAppStoreEntitlement(.lifetime, expires: nil)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.set(wasEverActive, forKey: Self.everActiveKey)
        LicenseStore.shared.setAppStoreEntitlement(nil, expires: nil)
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeController() -> TunnelController {
        TunnelController(engine: engine, profileStore: profileStore, sessionLog: sessionLog,
                         secrets: secrets, snapshots: snapshots, liveActivity: activity,
                         activitySettings: activitySettings)
    }

    @discardableResult
    private func adopt(_ controller: TunnelController,
                       server: UUID = UUID(),
                       serverName: String = "Home",
                       device: String = "device-1",
                       deviceName: String = "iPhone",
                       protocolID: ServiceID = .wireguardVPN) throws -> TunnelProfile {
        try controller.adopt(configurationText: configuration, protocolID: protocolID,
                             serverID: server, serverName: serverName,
                             deviceID: device, deviceName: deviceName)
    }

    private func wait(_ description: String,
                      timeout: TimeInterval = 2,
                      file: StaticString = #filePath, line: UInt = #line,
                      until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting until \(description)", file: file, line: line)
    }

    // MARK: - A tunnel already up at launch

    func testLaunchAsksTheSystemForATunnelItAlreadyRuns() async {
        _ = makeController()
        await wait("the engine is asked what runs") { self.engine.stateAsked > 0 }
    }

    // MARK: - The session log

    func testAConnectionOpensOneRowAndClosesIt() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        let started = Date()

        engine.emit(status: .connecting, profile: profile)
        engine.emit(status: .connected(since: started), profile: profile)
        await wait("the session is open") { self.sessionLog.running() != nil }

        engine.emit(status: .off, profile: profile,
                    statistics: TunnelStatistics(received: 2_048, sent: 1_024))
        await wait("the session is closed") { self.sessionLog.running() == nil }

        let sessions = sessionLog.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.profileID, profile.id)
        XCTAssertEqual(sessions.first?.startedAt.timeIntervalSince1970 ?? 0,
                       started.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(sessions.first?.statistics.received, 2_048)
        XCTAssertEqual(sessions.first?.statistics.sent, 1_024)
        XCTAssertNil(sessions.first?.failureReason)
    }

    /// A phone leaving Wi-Fi for cellular is the same session
    func testReassertingDoesNotOpenASecondRow() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        let started = Date()

        engine.emit(status: .connected(since: started), profile: profile)
        await wait("the session is open") { self.sessionLog.running() != nil }
        engine.emit(status: .reasserting(since: started), profile: profile)
        engine.emit(status: .connected(since: started), profile: profile)
        engine.emit(status: .off, profile: profile)
        await wait("the session is closed") { self.sessionLog.running() == nil }

        XCTAssertEqual(sessionLog.sessions().count, 1)
        XCTAssertEqual(sessionLog.sessions().first?.startedAt.timeIntervalSince1970 ?? 0,
                       started.timeIntervalSince1970, accuracy: 1,
                       "the timer a person is reading must not restart on a handover")
        _ = controller
    }

    func testAFailureBeforeAnythingCameUpIsStillWrittenDown() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connecting, profile: profile)
        engine.emit(status: .failed(reason: "handshake refused"), profile: profile)
        await wait("the failure is recorded") { !self.sessionLog.sessions().isEmpty }

        let sessions = sessionLog.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.failureReason, "handshake refused")
        XCTAssertNotNil(sessions.first?.endedAt, "a session nobody can end would run forever")
        _ = controller
    }

    func testAFailureAfterAConnectionClosesTheRunningRow() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the session is open") { self.sessionLog.running() != nil }
        engine.emit(status: .failed(reason: "peer went away"), profile: profile)
        await wait("the session is closed") { self.sessionLog.running() == nil }

        XCTAssertEqual(sessionLog.sessions().count, 1)
        XCTAssertEqual(sessionLog.sessions().first?.failureReason, "peer went away")
        _ = controller
    }

    func testTheLogNamesTheTunnelThatIsUpNotTheOneSelectedLater() async throws {
        let controller = makeController()
        let first = try adopt(controller, device: "device-1", deviceName: "iPhone")
        let second = try adopt(controller, device: "device-2", deviceName: "iPad")

        controller.selectedID = first.id
        engine.emit(status: .connected(since: Date()), profile: first)
        await wait("the session is open") { self.sessionLog.running() != nil }
        controller.selectedID = second.id

        XCTAssertEqual(controller.active?.id, first.id)
        XCTAssertEqual(sessionLog.running()?.deviceName, "iPhone")
    }

    func testActiveIsNilOnceTheTunnelIsOffSoTheCardFollowsTheSelection() async throws {
        let controller = makeController()
        let wireGuard = try adopt(controller, device: "device-1", protocolID: .wireguardVPN)
        let amnezia = try adopt(controller, device: "device-1", protocolID: .amneziaWG)

        controller.selectedID = wireGuard.id
        engine.emit(status: .connected(since: Date()), profile: wireGuard)
        await wait("the tunnel is up") { controller.active?.id == wireGuard.id }

        engine.emit(status: .off, profile: wireGuard)
        await wait("the tunnel is down") { controller.status == .off }
        controller.selectedID = amnezia.id

        XCTAssertNil(controller.active, "a tunnel that is off is not active")
        XCTAssertEqual((controller.active ?? controller.selected)?.id, amnezia.id,
                       "the card must name the tunnel now selected, not the one that was up")
    }

    // MARK: - The snapshot

    func testTheSnapshotFollowsTheStatus() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the snapshot says connected") {
            self.snapshots.read()?.tunnel.status.isActive == true
        }

        let tunnel = try XCTUnwrap(snapshots.read()?.tunnel)
        XCTAssertEqual(tunnel.profileID, profile.id)
        XCTAssertEqual(tunnel.serverName, "Home")
        XCTAssertEqual(tunnel.protocolName, "WireGuard")
        XCTAssertEqual(tunnel.profileCount, 1)
        XCTAssertTrue(tunnel.isSimulated, "this build carries no traffic and must say so")
        _ = controller
    }

    func testCountersAloneDoNotRewriteTheSnapshot() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        let since = Date()

        engine.emit(status: .connected(since: since), profile: profile,
                    statistics: TunnelStatistics(received: 10, sent: 10))
        await wait("the snapshot says connected") {
            self.snapshots.read()?.tunnel.status.isActive == true
        }

        engine.emit(status: .connected(since: since), profile: profile,
                    statistics: TunnelStatistics(received: 99_999, sent: 99_999))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(snapshots.read()?.tunnel.statistics.received, 10)
        XCTAssertEqual(controller.state.statistics.received, 99_999,
                       "the screen still gets every counter; only the file is rationed")
    }

    // MARK: - Profiles and their keys

    func testAdoptingAConfigurationKeepsTheTextOnlyInTheKeychain() throws {
        let controller = makeController()
        let profile = try adopt(controller)

        XCTAssertEqual(secrets.secret(for: profile.secretAccount), configuration)
        XCTAssertEqual(controller.profiles.map(\.id), [profile.id])
        let stored = try XCTUnwrap(profileStore.load().first)
        XCTAssertFalse("\(stored)".contains("PrivateKey"),
                       "a profile that carried its key would put it in every log line that printed one")
    }

    func testAnotherDevicesConfigurationIsNotThisDevicesOwn() throws {
        let controller = makeController()
        let server = UUID()
        try adopt(controller, server: server, device: "mac-1", deviceName: "MacBook Air")
        XCTAssertNil(controller.ownProfile(serverID: server, protocolID: .wireguardVPN))
        let own = try adopt(controller, server: server, device: "this-1",
                            deviceName: TunnelController.thisDeviceName)
        XCTAssertEqual(controller.ownProfile(serverID: server, protocolID: .wireguardVPN)?.id, own.id)
    }

    func testReAdoptingTheSameDeviceKeepsItsIdentity() throws {
        let controller = makeController()
        let server = UUID()
        let first = try adopt(controller, server: server)
        let second = try adopt(controller, server: server)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(controller.profiles.count, 1)
    }

    func testForgettingAServerTakesItsTunnelsAndTheirKeys() async throws {
        let controller = makeController()
        let doomed = UUID()
        let kept = UUID()
        let a = try adopt(controller, server: doomed, device: "device-1")
        let b = try adopt(controller, server: doomed, device: "device-2")
        let survivor = try adopt(controller, server: kept, serverName: "Office", device: "device-3")

        await controller.removeProfiles(forServer: doomed)

        XCTAssertEqual(controller.profiles.map(\.id), [survivor.id])
        XCTAssertNil(secrets.secret(for: a.secretAccount))
        XCTAssertNil(secrets.secret(for: b.secretAccount))
        XCTAssertNotNil(secrets.secret(for: survivor.secretAccount),
                        "another server's tunnel must not go with it")
    }

    func testRemovingTheRunningTunnelTakesItDownFirst() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the session is open") { self.sessionLog.running() != nil }

        await controller.remove(profile)

        XCTAssertEqual(engine.stopCount, 1, "the engine would otherwise hold a profile nothing can name")
        XCTAssertTrue(controller.profiles.isEmpty)
    }

    // MARK: - Refusing to connect

    func testConnectingWithNoTunnelsSaysSoAndNeverReachesTheEngine() async {
        let controller = makeController()

        await controller.connect()

        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(engine.started.isEmpty)
    }

    func testAProfileWhoseKeyIsGoneIsRefusedBeforeTheEngine() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        secrets.delete(profile.secretAccount)

        await controller.connect(profile)

        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(engine.started.isEmpty)
    }

    func testALockedCopyNeverReachesTheEngine() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        LicenseStore.shared.setAppStoreEntitlement(nil, expires: nil)

        await controller.connect(profile)

        XCTAssertTrue(engine.started.isEmpty)
        XCTAssertEqual(controller.errorMessage, LicenseGate.message(for: LicenseGate.reason))
    }

    func testConnectingHandsTheEngineTheConfigurationText() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        await controller.connect(profile)

        XCTAssertEqual(engine.started.count, 1)
        XCTAssertEqual(engine.started.first?.profile.id, profile.id)
        XCTAssertEqual(engine.started.first?.secret, configuration)
        XCTAssertNil(controller.errorMessage)
    }

    func testAnEngineThatRefusesToStartLeavesTheReasonOnScreen() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        engine.startError = TunnelEngineError.systemRefused("no entitlement")

        await controller.connect(profile)

        XCTAssertEqual(controller.errorMessage, "no entitlement")
    }

    func testAReasonFromThePackageIsPutIntoWordsBeforeItReachesTheScreen() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        engine.startError = TunnelEngineError.configurationUnreadable(.missingEndpoint)

        await controller.connect(profile)

        XCTAssertEqual(controller.errorMessage,
                       VPNText.message(for: WireGuardQuickConfig.ParseError.missingEndpoint))
        XCTAssertNotEqual(controller.errorMessage, "",
                          "an unworded reason would reach the screen as an empty label")
    }

    func testToggleTakesDownWhatIsUp() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the controller sees the connection") { controller.status.isActive }

        await controller.toggle()

        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertTrue(engine.started.isEmpty)
    }

    // MARK: - The lock-screen session

    /// One activity per SESSION
    func testAHandoverUpdatesTheLockScreenRatherThanRestartingIt() async throws {
        let controller = makeController()
        let profile = try adopt(controller)
        let since = Date()

        engine.emit(status: .connected(since: since), profile: profile)
        await wait("the activity has started") { self.activity.starts == 1 }
        engine.emit(status: .reasserting(since: since), profile: profile)
        engine.emit(status: .connected(since: since), profile: profile)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(activity.starts, 1)
        XCTAssertEqual(activity.ends, 0)
        XCTAssertEqual(activity.calls.dropFirst(),
                       [.update(status: .reasserting(since: since)),
                        .update(status: .connected(since: since))])
        _ = controller
    }

    func testTheLockScreenSessionEndsWithTheTunnel() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the activity has started") { self.activity.starts == 1 }
        engine.emit(status: .off, profile: profile)
        await wait("the activity has ended") { self.activity.ends == 1 }

        XCTAssertEqual(activity.starts, 1)
        _ = controller
    }

    func testTheLockScreenIsToldWhetherTheTunnelIsReal() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the activity has started") { self.activity.starts == 1 }

        guard case .start(_, _, let isSimulated)? = activity.calls.first else {
            return XCTFail("no activity was started")
        }
        XCTAssertEqual(isSimulated, controller.isDemonstration)
    }

    func testNoLockScreenSessionWhenTheSwitchIsOff() async throws {
        activitySettings.showsVPNSession = false
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the tunnel is up") { controller.state.status.isActive }
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(activity.starts, 0)
    }

    func testTurningTheSwitchOffEndsAndOnRestartsTheSession() async throws {
        let controller = makeController()
        let profile = try adopt(controller)

        engine.emit(status: .connected(since: Date()), profile: profile)
        await wait("the activity has started") { self.activity.starts == 1 }
        activitySettings.showsVPNSession = false
        XCTAssertEqual(activity.ends, 1)
        activitySettings.showsVPNSession = true
        XCTAssertEqual(activity.starts, 2)
    }

    func testTheSwitchIsOnUntilTurnedOffAndRemembered() {
        XCTAssertTrue(activitySettings.showsVPNSession)
        activitySettings.showsVPNSession = false
        XCTAssertFalse(LiveActivitySettings(defaults: defaults).showsVPNSession)
    }
}
