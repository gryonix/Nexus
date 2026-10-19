// Opens SSH sessions over a socket the app owns, so a failed
// or cancelled sign-in closes it at once instead of leaving
// sshd waiting out its login grace time.

import Citadel
import Foundation
import NIOCore
import ServerControl

public enum SSHDial {
    /// Pauses before redialling a server that hung up silently
    public static let redialPauses: [Duration] = [.seconds(15), .seconds(30)]

    /// One signed-in session, redialled while the server drops us unheard
    public static func connect(_ settings: SSHClientSettings,
                               through proxy: ProxyConnect.Endpoint? = nil,
                               pauses: [Duration] = redialPauses) async throws -> SSHClient {
        var left = pauses[...]
        while true {
            do {
                return try await connectOnce(settings, through: proxy)
            } catch is HungUpSilently {
                guard let pause = left.popFirst() else {
                    throw ServerControlError.connectionFailed(
                        "\(settings.host) closed the connection before answering; " +
                        "sshd may be refusing this address for a while")
                }
                try await Task.sleep(for: pause)
            }
        }
    }

    /// The server closed the socket without sending a byte
    struct HungUpSilently: Error {}

    static func connectOnce(_ settings: SSHClientSettings,
                            through proxy: ProxyConnect.Endpoint?) async throws -> SSHClient {
        let link = try await ProxyConnect.link(to: settings.host, port: settings.port, through: proxy,
                                               group: settings.group, timeout: settings.connectTimeout)
        let door: ProxyConnect.Door
        do {
            door = try await ProxyConnect.door(to: link, group: settings.group)
        } catch {
            try? await link.channel.close()
            throw error
        }
        var dialled = settings
        dialled.host = "127.0.0.1"
        dialled.port = door.port
        do {
            let client = try await withTaskCancellationHandler {
                try await SSHClient.connect(to: dialled)
            } onCancel: {
                Task { await door.abort() }
            }
            await door.close()
            return client
        } catch {
            let unheard = !door.serverSpoke && !Task.isCancelled
            await door.abort()
            throw unheard ? HungUpSilently() : error
        }
    }
}
