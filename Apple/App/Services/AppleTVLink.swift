#if os(iOS)
import Foundation
import Network
import ServerControl
import TVLink
import UIKit

@MainActor
final class AppleTVLink: ObservableObject {
    static let shared = AppleTVLink()

    @Published private(set) var nearby: [TVNearby] = []
    @Published private(set) var paired: [TVPairedTV] = []

    private let store: TVPairedTVStore
    private let phone: TVPeer
    private var browser: TVBrowser?
    private var watchers = 0

    private init() {
        let directory = AppSupportDirectory.base.appendingPathComponent("TVLink", isDirectory: true)
        store = TVPairedTVStore(fileURL: directory.appendingPathComponent("tvs.json"), secrets: KeychainTVSecrets())
        phone = TVPeer(id: DeviceIdentity.uid, name: UIDevice.current.name)
        paired = store.all()
    }

    func startBrowsing() {
        watchers += 1
        guard browser == nil else { return }
        nearby = []
        let browser = TVBrowser { [weak self] found in
            Task { @MainActor in self?.nearby = found }
        }
        browser.start()
        self.browser = browser
    }

    func stopBrowsing() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        browser?.stop()
        browser = nil
        nearby = []
    }

    /// TVs on the network this phone has not paired with
    var unpaired: [TVNearby] {
        nearby.filter { tv in !paired.contains { $0.id == tv.tvID } }
    }

    /// Connects; the TV now shows its code
    func beginPairing(_ tv: TVNearby) async throws -> TVPairingAttempt {
        try await TVPairingAttempt.start(tv.endpoint, phone: phone)
    }

    /// Checks the typed code and remembers the TV
    func finishPairing(_ attempt: TVPairingAttempt, code: TVPairingCode) async throws {
        let result = try await attempt.enter(code)
        let address = await attempt.address
        try store.save(TVPairedTV(id: result.peer.id, name: result.peer.name, address: address, pairedAt: Date()),
                       pairingKey: result.pairingKey)
        paired = store.all()
        await vouch(store.record(result.peer.id))
    }

    /// Quietly vouches to TVs whose app is on screen
    func vouchAll() async {
        await vouch { Self.awake(self.paired, seen: self.nearby, now: Date()) }
    }

    /// Vouches to every paired TV Bonjour finds
    func confirmNow() async {
        await vouch { Self.seen(self.paired, seen: self.nearby) }
    }

    private func vouch(_ targets: @MainActor () -> [TVPairedTV]) async {
        guard !paired.isEmpty else { return }
        startBrowsing()
        defer { stopBrowsing() }
        try? await Task.sleep(for: .seconds(2))
        for tv in targets() { await vouch(tv) }
    }

    nonisolated static func awake(_ paired: [TVPairedTV], seen: [TVNearby], now: Date) -> [TVPairedTV] {
        Self.seen(paired, seen: seen.filter { $0.isAwake(now: now) })
    }

    nonisolated static func seen(_ paired: [TVPairedTV], seen: [TVNearby]) -> [TVPairedTV] {
        paired.filter { tv in seen.contains { $0.tvID == tv.id } }
    }

    private func vouch(_ tv: TVPairedTV?) async {
        guard let tv else { return }
        let answers = try? await exchange([TVMessage(t: .licence, licence: Self.licence())], with: tv,
                                          lastAddress: false)
        guard answers?.first?.t == .ok else { return }
        var updated = tv
        updated.vouchedAt = Date()
        try? store.save(updated)
        paired = store.all()
    }

    /// Sends servers with their keys over the encrypted link
    func send(_ deployments: [Deployment], to tv: TVPairedTV) async throws {
        let items = try deployments.map { deployment in
            TVSentServer(id: deployment.id.uuidString, name: deployment.name,
                         transfer: try DeploymentTransferService.encode(DeploymentTransferService.export(deployment)))
        }
        let answers = try await exchange([TVMessage(t: .put, items: items, licence: Self.licence())], with: tv)
        guard let answer = answers.first, answer.t == .servers else {
            throw TVLinkError.connectionFailed(answers.first?.code ?? "")
        }
        var updated = tv
        updated.sent = answer.items ?? []
        updated.vouchedAt = Date()
        try? store.save(updated)
        paired = store.all()
    }

    /// Unpairs on the TV when it answers, and here regardless
    func forget(_ tv: TVPairedTV) async {
        _ = try? await exchange([TVMessage(t: .unpair)], with: tv)
        store.remove(tv.id)
        paired = store.all()
    }

    private func exchange(_ requests: [TVMessage], with tv: TVPairedTV,
                          lastAddress: Bool = true) async throws -> [TVMessage] {
        guard let key = store.pairingKey(tv.id), let endpoint = endpoint(of: tv, lastAddress: lastAddress) else {
            throw TVLinkError.closed
        }
        return try await TVLinkClient.exchange(requests, at: endpoint, phone: phone, tvID: tv.id, pairingKey: key)
    }

    /// Bonjour first, the last address if allowed
    private func endpoint(of tv: TVPairedTV, lastAddress: Bool) -> NWEndpoint? {
        let found = nearby.first { $0.tvID == tv.id }?.endpoint
        return lastAddress ? found ?? tv.address?.endpoint : found
    }

    /// This phone's license, as the TV checks it
    static func licence() -> TVLicenceVouch {
        let store = LicenseStore.shared
        guard case .active(let plan, let expires, _) = store.status else { return TVLicenceVouch(active: false) }
        return TVLicenceVouch(active: true, plan: plan.rawValue,
                              expires: expires.map { Int($0.timeIntervalSince1970) },
                              token: store.deviceToken, device: DeviceIdentity.uid)
    }
}
#endif
