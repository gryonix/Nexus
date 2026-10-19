import Foundation
import ServiceCatalog
import VPNProfile
import VPNTunnel

enum VPNText {
    static func message(for error: Error) -> String {
        switch error {
        case let failure as TunnelEngineError:
            return message(for: failure)
        case let failure as TunnelProfileBuilder.Failure:
            return message(for: failure)
        case let failure as WireGuardQuickConfig.ParseError:
            return message(for: failure)
        case let failure as OpenVPNProfileConfig.ParseError:
            return message(for: failure)
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func message(for error: TunnelEngineError) -> String {
        switch error {
        case .protocolNotCarried(let id):
            return refusal(for: id) ?? UIL10n.string("This protocol cannot be brought up here.")
        case .configurationUnreadable(let reason):
            return reason.map(message(for:))
                ?? UIL10n.string("This device's configuration could not be read.")
        case .configurationMissing:
            return UIL10n.string("This device's configuration is missing. Fetch it from the server again.")
        case .systemRefused(let systemMessage):
            return systemMessage
        }
    }

    static func message(for failure: TunnelProfileBuilder.Failure) -> String {
        switch failure {
        case .protocolNotCarried(let id):
            return refusal(for: id) ?? UIL10n.string("This protocol cannot be brought up here.")
        case .unreadable(let reason):
            return reason.map(message(for:))
                ?? UIL10n.string("This device's configuration could not be read.")
        case .unreadableLink(let reason):
            return message(for: reason)
        case .unreadableProfile(let reason):
            return reason.map(message(for:))
                ?? UIL10n.string("This device's configuration could not be read.")
        }
    }

    /// A share link that could not become a tunnel
    static func message(for error: ProxyLinkConfig.ParseError) -> String {
        switch error {
        case .noLink:
            return UIL10n.string("This device's configuration is not a connection link.")
        case .noEndpoint:
            return UIL10n.string("The link names no server and port to connect to.")
        case .noCredential:
            return UIL10n.string("The link says where to connect but carries no credential.")
        case .unsupportedTransport(let name):
            return UIL10n.string("This app cannot carry a “%@” connection yet. The server can hand this device out over TCP instead.", name)
        }
    }

    static func message(for error: WireGuardQuickConfig.ParseError) -> String {
        switch error {
        case .missingInterface:
            return UIL10n.string("The configuration has no [Interface] section.")
        case .missingPeer:
            return UIL10n.string("The configuration has no [Peer] section.")
        case .missingEndpoint:
            return UIL10n.string("The [Peer] section has no Endpoint.")
        case .severalPeers:
            return UIL10n.string("The configuration has more than one [Peer] section, and this app carries only one.")
        }
    }

    static func message(for error: OpenVPNProfileConfig.ParseError) -> String {
        switch error {
        case .noDirectives:
            return UIL10n.string("The file has no OpenVPN settings in it.")
        case .noRemote:
            return UIL10n.string("The profile names no server to connect to (no “remote” line).")
        case .unterminatedInlineBlock(let name):
            return UIL10n.string("The profile's <%@> section is never closed.", name)
        }
    }

    /// Why a protocol is not offered on this device
    static func refusal(for id: ServiceID) -> String? {
        guard !TunnelCapableProtocols.isIntegrated(id) else { return nil }
        return UIL10n.string("%@ runs its own client. gryonixNexus hands it the configuration — the tunnel itself is brought up by that app.",
                             id.displayName)
    }

    /// A stored `failureReason`, said in the reader's language
    static func failureReason(_ stored: String) -> String {
        switch stored {
        case TunnelSession.interruptedMarker:
            return UIL10n.string("Interrupted — the app stopped before this session ended.")
        case TunnelSession.stoppedByItselfMarker:
            return UIL10n.string("The tunnel stopped by itself without an error. iOS ends a tunnel that uses too much memory.")
        default:
            return stored
        }
    }
}
