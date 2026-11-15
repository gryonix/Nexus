import Foundation
import ServerControl
import TVLink
import UIKit

/// Adds servers a paired phone sent to this TV's list
struct TVServerInbox: TVServerReceiving {
    func receive(_ items: [TVSentServer]) throws {
        let store = FileDeploymentStore()
        for item in items {
            guard let data = item.transfer, let transfer = try? DeploymentTransferService.decode(data) else {
                throw TVLinkStoreError.unusable(item.id)
            }
            do {
                try DeploymentTransferService.apply(transfer, store: store)
            } catch {
                throw TVLinkStoreError.cannotWrite
            }
        }
        Task { @MainActor in
            NotificationCenter.default.post(name: .cloudSyncChangedServers, object: nil)
            CloudSync.shared.scheduleSync()
        }
    }
}

@MainActor
final class TVLinkHostModel: ObservableObject {
    static let shared = TVLinkHostModel()

    @Published private(set) var code: TVPairingCode
    @Published private(set) var phones: [TVPairedPhone] = []
    /// A phone is knocking: the code goes full screen
    @Published private(set) var knocking: TVPeer?
    @Published private(set) var port: UInt16?
    @Published private(set) var failure: String?

    let tv: TVPeer
    let phoneStore: TVPhoneStore
    private let inbox: TVLinkInbox
    private var server: TVLinkServer?
    private var bridge: TVLinkBridge?
    private var ticker: Task<Void, Never>?
    private var listening = false

    private init() {
        let directory = AppSupportDirectory.base.appendingPathComponent("TVLink", isDirectory: true)
        phoneStore = TVPhoneStore(fileURL: directory.appendingPathComponent("phones.json"),
                                  secrets: KeychainTVSecrets())
        inbox = TVLinkInbox(servers: TVServerInbox(), phones: phoneStore)
        tv = TVPeer(id: DeviceIdentity.uid, name: UIDevice.current.name)
        code = TVPairingCode.random(SystemTVLinkRandom())
        reloadPhones()
    }

    /// Starts listening and keeps the license current
    func start() {
        guard server == nil else { return }
        let bridge = TVLinkBridge(model: self, inbox: inbox, phones: phoneStore)
        let server = TVLinkServer(tv: tv, host: bridge)
        self.bridge = bridge
        self.server = server
        listen()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.reloadPhones()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    /// Listens again when the app is back on screen
    func resume() {
        guard !listening else { return }
        listen()
    }

    /// Stops listening so a sleeping TV stays asleep
    func pause() {
        listening = false
        server?.stop()
        port = nil
    }

    private func listen() {
        guard let server else { return }
        listening = true
        Task {
            do {
                let opened = try await server.start()
                if listening { port = opened } else { server.stop() }
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Re-reads paired phones and what they say about the license
    func reloadPhones() {
        phones = phoneStore.all().sorted { $0.pairedAt < $1.pairedAt }
        let best = TVLicenceRule.best(phones)
        LicenseStore.shared.setPhoneLicence(best?.plan, until: best?.until)
    }

    /// When the phones' word runs out, if any phone vouched
    var licenceEnds: Date? { TVLicenceRule.best(phones)?.until }

    func forget(_ phone: TVPairedPhone) {
        inbox.forget(phone.id)
        reloadPhones()
    }

    fileprivate func knocked(_ phone: TVPeer) {
        knocking = phone
    }

    fileprivate func pairingEnded(_ phone: TVPeer, result: TVPairingResult?, codeTried: Bool) {
        knocking = nil
        if result != nil || codeTried { code = TVPairingCode.random(SystemTVLinkRandom()) }
        if let result {
            let now = Date()
            do {
                try phoneStore.save(TVPairedPhone(id: phone.id, name: phone.name, pairedAt: now, lastSeen: now),
                                    pairingKey: result.pairingKey)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
        }
        reloadPhones()
    }

    fileprivate func currentCode() -> TVPairingCode { code }
}

/// Carries listener callbacks onto the main actor
final class TVLinkBridge: TVLinkHost, @unchecked Sendable {
    private weak var model: TVLinkHostModel?
    private let inbox: TVLinkInbox
    private let phones: TVPhoneStore

    init(model: TVLinkHostModel, inbox: TVLinkInbox, phones: TVPhoneStore) {
        self.model = model
        self.inbox = inbox
        self.phones = phones
    }

    func pairingCode(for phone: TVPeer) async -> TVPairingCode {
        await MainActor.run {
            model?.knocked(phone)
            return model?.currentCode() ?? TVPairingCode.random(SystemTVLinkRandom())
        }
    }

    func pairingEnded(phone: TVPeer, result: TVPairingResult?, codeTried: Bool) async {
        await MainActor.run { model?.pairingEnded(phone, result: result, codeTried: codeTried) }
    }

    func pairingKey(for phoneID: String) async -> Data? {
        phones.pairingKey(phoneID)
    }

    func handle(_ request: TVMessage, from phoneID: String) async -> TVMessage {
        let answer = inbox.handle(request, from: phoneID)
        await MainActor.run { model?.reloadPhones() }
        return answer
    }
}
