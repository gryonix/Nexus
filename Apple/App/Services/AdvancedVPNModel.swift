import Foundation
import VPNProfile
import VPNTunnel

@MainActor
final class AdvancedVPNModel: ObservableObject {
    static let shared = AdvancedVPNModel()

    @Published private(set) var profile = AdvancedProfile()
    @Published private(set) var report: AdvancedImportReport?
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private(set) var traffic: AdvancedTraffic?

    private let secrets: any TunnelSecretStoring
    private let account = "advanced.profile"
    nonisolated static let refreshInterval: TimeInterval = 24 * 3600
    static let downloadLimit = 8 << 20

    init(secrets: any TunnelSecretStoring = KeychainTunnelSecretStore()) {
        self.secrets = secrets
        profile = load()
    }

    // MARK: Storage

    private func load() -> AdvancedProfile {
        guard let text = secrets.secret(for: account) else { return AdvancedProfile() }
        return (try? AdvancedProfileCoding.decode(text)) ?? AdvancedProfile()
    }

    func update(_ change: (inout AdvancedProfile) -> Void) {
        var copy = profile
        change(&copy)
        profile = copy
        if let text = try? AdvancedProfileCoding.encode(copy) { try? secrets.store(text, for: account) }
    }

    // MARK: Import

    func importText(_ text: String) {
        let found = SubscriptionImport.parse(body: text)
        absorb(found)
        report = found
    }

    private func absorb(_ found: AdvancedImportReport) {
        update { profile in
            profile.merge(servers: found.servers)
            for rule in found.rules where !profile.rules.contains(where: {
                $0.kind == rule.kind && $0.value == rule.value && $0.action == rule.action
            }) { profile.rules.append(rule) }
        }
    }

    func addSubscription(_ urlText: String) async {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isFetchable(text) else {
            message = UIL10n.string("Use an https:// address.")
            return
        }
        let subscription = AdvancedSubscription(name: URL(string: text)?.host ?? text, url: text)
        update { $0.subscriptions.append(subscription) }
        await refresh(subscription.id)
    }

    func refresh(_ subscriptionID: String) async {
        guard let subscription = profile.subscriptions.first(where: { $0.id == subscriptionID }) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let found = SubscriptionImport.parse(body: try await Self.download(subscription.url))
            apply(found, to: subscriptionID)
            report = found
            message = nil
        } catch {
            message = UIL10n.string("The subscription could not be read.")
        }
    }

    private func apply(_ found: AdvancedImportReport, to subscriptionID: String) {
        update { profile in
            guard let index = profile.subscriptions.firstIndex(where: { $0.id == subscriptionID }) else { return }
            let old = Set(profile.subscriptions[index].serverIDs)
            let fresh = Set(found.servers.map(\.id))
            let others = Set(profile.subscriptions.enumerated().filter { $0.offset != index }.flatMap(\.element.serverIDs))
            profile = profile.removing(serverIDs: old.subtracting(fresh).subtracting(others))
            profile.merge(servers: found.servers)
            profile.subscriptions[index].serverIDs = found.servers.map(\.id)
            profile.subscriptions[index].updatedAt = Date()
        }
    }

    func refreshDue() async {
        for subscription in profile.subscriptions where Self.isDue(subscription.updatedAt) {
            await refresh(subscription.id)
        }
        for list in profile.blockLists where Self.isDue(list.updatedAt) { await refreshBlockList(list.id) }
        if !AdvancedGeoIP.codes(in: profile.rules).isEmpty,
           Self.isDue(profile.geoip.updatedAt, interval: Self.geoipRefreshInterval) { await refreshGeoIP() }
    }

    static func isDue(_ date: Date?, now: Date = Date(), interval: TimeInterval = refreshInterval) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= interval
    }

    // MARK: GeoIP

    static let geoipRefreshInterval: TimeInterval = 7 * 24 * 3600
    static let geoipDownloadLimit = 64 << 20

    /// Rule country codes missing from the database
    var missingCountries: Set<String> {
        AdvancedGeoIP.codes(in: profile.rules).subtracting(profile.geoip.ranges.keys)
    }

    func refreshGeoIP() async {
        let codes = AdvancedGeoIP.codes(in: profile.rules)
        let address = profile.geoip.url
        guard !codes.isEmpty else { return }
        guard Self.isFetchable(address) else {
            message = UIL10n.string("Use an https:// address.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await Self.downloadData(address, limit: Self.geoipDownloadLimit)
            let ranges = try await Task.detached { try GeoIPDatParser.ranges(in: data, codes: codes) }.value
            update { $0.geoip.ranges = ranges; $0.geoip.updatedAt = Date() }
            message = nil
        } catch {
            message = UIL10n.string("The country database could not be read.")
        }
    }

    // MARK: Block lists

    func addBlockList(_ urlText: String) async {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isFetchable(text) else {
            message = UIL10n.string("Use an https:// address.")
            return
        }
        let list = AdvancedBlockList(url: text)
        update { $0.blockLists.append(list) }
        await refreshBlockList(list.id)
    }

    func refreshBlockList(_ id: String) async {
        guard let list = profile.blockLists.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let domains = BlockListParser.domains(in: try await Self.download(list.url))
            update { profile in
                guard let index = profile.blockLists.firstIndex(where: { $0.id == id }) else { return }
                profile.blockLists[index].domains = domains
                profile.blockLists[index].updatedAt = Date()
            }
            message = nil
        } catch {
            message = UIL10n.string("The list could not be read.")
        }
    }

    // MARK: Download

    static func isFetchable(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    private static func download(_ address: String) async throws -> String {
        let data = try await downloadData(address, limit: downloadLimit)
        guard let text = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return text
    }

    private static func downloadData(_ address: String, limit: Int) async throws -> Data {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= limit else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Tunnel

    func apply(to tunnel: TunnelController, connect: Bool) async {
        if profile.activeID == nil, let first = profile.servers.first { update { $0.activeID = first.id } }
        do {
            let adopted = try tunnel.adoptAdvanced(profile)
            message = nil
            if connect || tunnel.state.status.isActive { await tunnel.choose(adopted, reconnectingSame: true) }
        } catch {
            message = UIL10n.string("Choose a server or a group first.")
        }
    }

    func refreshTraffic(from tunnel: TunnelController) async {
        traffic = await tunnel.advancedTraffic()
    }
}

enum AdvancedProfileCoding {
    static func encode(_ profile: AdvancedProfile) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(profile), as: UTF8.self)
    }

    static func decode(_ text: String) throws -> AdvancedProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdvancedProfile.self, from: Data(text.utf8))
    }
}
