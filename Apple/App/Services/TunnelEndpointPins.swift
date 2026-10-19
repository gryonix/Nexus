import Foundation
import VPNProfile
import VPNTunnel

/// Addresses pinned per device tunnel instead of the domain
@MainActor
final class TunnelEndpointPins: ObservableObject {
    static let shared = TunnelEndpointPins()

    enum Refusal: Error, Equatable {
        case notFound
        case privateAddress(String)
    }

    @Published private var pins: [String: EndpointPin]
    private let defaults: UserDefaults
    private static let key = "tunnel.endpointPins"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key) ?? Data()
        pins = (try? JSONDecoder().decode([String: EndpointPin].self, from: data)) ?? [:]
    }

    /// Whether this tunnel can be reached by address at all
    static func canPin(_ profile: TunnelProfile) -> Bool {
        guard let host = EndpointPin.split(profile.endpoint)?.host else { return false }
        let datapath = TunnelCapableProtocols.datapath(for: profile.protocolID)
        return (datapath == .wireGuardKit || datapath == .xray) && !EndpointPin.isAddress(host)
    }

    /// The pin for this tunnel while its domain matches
    func pin(for profile: TunnelProfile) -> EndpointPin? {
        guard Self.canPin(profile), let pin = pins[Self.key(profile)],
              pin.replacingHost(of: profile.endpoint) != nil else { return nil }
        return pin
    }

    /// Looks the domain up now and keeps its public address
    func pinAddress(of profile: TunnelProfile) async throws -> EndpointPin {
        guard Self.canPin(profile), let host = EndpointPin.split(profile.endpoint)?.host else {
            throw Refusal.notFound
        }
        let found = await Task.detached { Self.addresses(of: host) }.value
        let reachable = found.filter(EndpointPin.isPublic)
        guard let address = reachable.first(where: { !$0.contains(":") }) ?? reachable.first else {
            let shown = found.first { !$0.contains(":") } ?? found.first
            throw shown.map(Refusal.privateAddress) ?? Refusal.notFound
        }
        let pin = EndpointPin(host: host, address: address)
        pins[Self.key(profile)] = pin
        save()
        return pin
    }

    func unpin(_ profile: TunnelProfile) {
        guard pins.removeValue(forKey: Self.key(profile)) != nil else { return }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func key(_ profile: TunnelProfile) -> String {
        "\(profile.serverID.uuidString)/\(profile.protocolID.rawValue)/\(profile.deviceID)"
    }

    /// Every numeric address the system resolves the host to
    nonisolated static func addresses(of host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0 else { return [] }
        defer { freeaddrinfo(found) }
        var addresses: [String] = []
        var cursor = found
        while let info = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer,
                           socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
            cursor = info.pointee.ai_next
        }
        return addresses
    }
}
