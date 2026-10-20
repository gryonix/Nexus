import AgentControl
import Foundation
import ServerControl
import ServiceCatalog
import VPNTunnel

extension TunnelController {
    /// Moves this device to that server and protocol, settings kept
    func switchTo(deployment: Deployment, protocolID: ServiceID) async {
        let carry = (active ?? selected).map { TunnelCarry(of: $0, pinned: TunnelEndpointPins.shared.pin(for: $0) != nil) }
        if let kept = ThisDeviceTunnelChoices.keptProfile(in: profiles, serverID: deployment.id,
                                                          protocolID: protocolID, isOwn: Self.isThisDevice) {
            let ready = await carrying(carry, to: kept, in: deployment)
            await applyReach(carry, to: ready)
            await choose(ready)
        } else {
            await useAsThisDevice(deployment: deployment, protocolID: protocolID, carry: carry)
        }
    }

    /// A configuration whose DNS matches the carried one
    func carriedConfiguration(of clientID: String, protocolID: ServiceID, from viewModel: DashboardViewModel,
                              carry: TunnelCarry?) async -> VPNClientConfiguration? {
        let first = await viewModel.vpnClientConfiguration(protocol: protocolID, clientID: clientID)
        guard let carry, !carry.dns.isEmpty, let first, first.dns != carry.dns else { return first }
        await viewModel.setVPNClientDNS(protocol: protocolID, clientID: clientID, dns: carry.dns)
        return await viewModel.vpnClientConfiguration(protocol: protocolID, clientID: clientID) ?? first
    }

    /// This device's kept profile, given the carried DNS first
    private func carrying(_ carry: TunnelCarry?, to profile: TunnelProfile, in deployment: Deployment) async -> TunnelProfile {
        guard let carry, !carry.dns.isEmpty, profile.dns != carry.dns,
              Self.isThisDevice(profile.deviceName), #available(macOS 15.0, *) else { return profile }
        let viewModel = DashboardViewModel(deployment: deployment)
        guard let configuration = await carriedConfiguration(of: profile.deviceID, protocolID: profile.protocolID,
                                                             from: viewModel, carry: carry),
              let updated = try? adopt(configurationText: configuration.text, protocolID: profile.protocolID,
                                       serverID: profile.serverID, serverName: profile.serverName,
                                       deviceID: profile.deviceID, deviceName: profile.deviceName,
                                       dns: configuration.dns) else { return profile }
        return updated
    }

    /// Keeps reaching the server by address or by name
    func applyReach(_ carry: TunnelCarry?, to profile: TunnelProfile) async {
        guard let carry, TunnelEndpointPins.canPin(profile) else { return }
        let pins = TunnelEndpointPins.shared
        if carry.pinned, pins.pin(for: profile) == nil {
            _ = try? await pins.pinAddress(of: profile)
        } else if !carry.pinned {
            pins.unpin(profile)
        }
    }
}

/// What a switch keeps from the tunnel it leaves
struct TunnelCarry: Equatable {
    var dns: [String]
    var pinned: Bool

    init(of profile: TunnelProfile, pinned: Bool) {
        dns = profile.dns
        self.pinned = pinned
    }
}
