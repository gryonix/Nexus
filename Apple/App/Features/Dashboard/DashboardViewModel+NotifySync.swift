import AgentClient
import AgentControl
import CryptoKit
import Foundation

extension DashboardViewModel {
    /// Where the last synced wishes for a server are remembered
    static func notifySyncedKey(for deploymentID: UUID) -> String { "notify.synced.\(deploymentID)" }

    /// Gives this server the app-wide notification wishes
    @available(macOS 15.0, *)
    func syncNotifyPreferences(_ defaults: UserDefaults = .standard) async {
        guard canManageNotifications, deployment.usesAgent else { return }
        let wanted = NotifyPreferences.current(defaults)
        let channel = NotifyChannelDefault.current(defaults)
        let key = Self.notifySyncedKey(for: deployment.id)
        let language = ContentLanguageSetting.current.rawValue
        let own = defaults.object(forKey: NotifyChannelDefault.ownKey(for: deployment.id)) as? Bool
        let mark = wanted.fingerprint + language + "k" + "h\(deployment.agentHosts.count)"
            + Self.tokenMark(PushRegistration.shared.token) + "p1" + channel.fingerprint + "\(own.map { $0 ? 1 : 0 } ?? 2)"
        let checkedThisLaunch = Self.notifyCheckedThisLaunch.contains(deployment.id)
        guard defaults.string(forKey: key) != mark || !checkedThisLaunch else { return }
        do {
            let operations = try await notifyOperations()
            let current = try await operations.settings()
            RelayServers.remember(current.serverID, as: deployment.id, host: deployment.servicesHost)
            let appKey = await Self.devicePublicKey(for: deployment)
            let follows = !NotifyChannelDefault.keepsOwn(current, deploymentID: deployment.id,
                                                         wanted: channel, defaults: defaults)
            let request = Self.notifySyncRequest(current: current, wanted: wanted, language: language, appKey: appKey,
                                                 channel: follows ? channel : nil)
            if let request { _ = try await operations.save(request) }
            if (request?.channel ?? current.channel) == .relay, let token = PushRegistration.shared.token {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                try await operations.register(platform: PushRegistration.shared.platform, token: token,
                                              appVersion: version, locale: ContentLanguageSetting.current.rawValue,
                                              muted: wanted.muted, proof: DevicePushProof.proof,
                                              name: PushRegistration.deviceName)
            }
            PushRelays.remember(current.relayURL)
            guard await mirrorNotify(try await operations.settings()) else { return }
            Self.notifyCheckedThisLaunch.insert(deployment.id)
            defaults.set(mark, forKey: key)
        } catch {
            return
        }
    }

    /// Servers whose every machine knows this phone since launch
    @MainActor static var notifyCheckedThisLaunch: Set<UUID> = []

    /// A new push token makes the server learn it again
    static func tokenMark(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(token.utf8))
        return "t" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Every other machine sends its alerts the same way
    @available(macOS 15.0, *)
    @discardableResult
    func mirrorNotify(_ primary: Gryonixnexusd_V1_NotifySettings) async -> Bool {
        let others = deployment.agentHosts.filter { $0 != deployment.servicesHost }
        guard !others.isEmpty else { return true }
        guard let runner = try? await commandSession() else { return false }
        let appKey = await Self.devicePublicKey(for: deployment)
        var allDone = true
        for host in others {
            do {
                let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: host)
                let operations = AgentNotifyOperations(client: client, gate: AgentChannelGate.shared(for: deployment.id))
                let current = try await operations.settings()
                RelayServers.remember(current.serverID, as: deployment.id, host: host)
                if let request = Self.notifyMirrorRequest(primary: primary, current: current, appKey: appKey) {
                    try await operations.save(request)
                }
                try await registerThisDevice(primary, on: operations)
            } catch {
                allDone = false
            }
        }
        return allDone
    }

    @available(macOS 15.0, *)
    private func registerThisDevice(_ primary: Gryonixnexusd_V1_NotifySettings,
                                    on operations: AgentNotifyOperations) async throws {
        guard primary.channel == .relay, let token = PushRegistration.shared.token else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        try await operations.register(platform: PushRegistration.shared.platform, token: token, appVersion: version,
                                      locale: ContentLanguageSetting.current.rawValue,
                                      muted: NotifyPreferences.current().muted, proof: DevicePushProof.proof,
                                      name: PushRegistration.deviceName)
    }

    /// What another machine needs to match the main one
    static func notifyMirrorRequest(primary: Gryonixnexusd_V1_NotifySettings,
                                    current: Gryonixnexusd_V1_NotifySettings,
                                    appKey: String) -> Gryonixnexusd_V1_SetNotifySettingsRequest? {
        var wanted = NotifyDraft.request(from: primary)
        let keyKnown = appKey.isEmpty || current.quietKeys.contains { appKey.hasPrefix($0) }
        guard NotifyDraft.request(from: current) != wanted || !keyKnown else { return nil }
        wanted.appPublicKey = appKey
        return wanted
    }

    /// The request a server needs to match, if any
    static func notifySyncRequest(current: Gryonixnexusd_V1_NotifySettings, wanted: NotifyPreferences,
                                  language: String, appKey: String,
                                  channel: NotifyChannelDefault? = nil) -> Gryonixnexusd_V1_SetNotifySettingsRequest? {
        let checks = current.customChecks ? current.checks : wanted.checks
        let keyKnown = appKey.isEmpty || current.quietKeys.contains { appKey.hasPrefix($0) }
        let channelInStep = channel?.matches(current) ?? true
        guard current.checks != checks || current.language != language || !keyKnown || !channelInStep else { return nil }
        var request = NotifyDraft.request(from: current)
        if let channel { request = channel.applied(to: request) }
        request.checks = checks
        request.language = language
        request.appPublicKey = appKey
        return request
    }
}
