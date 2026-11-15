import Foundation
import ServerControl
import ServerControlSSH
import SwiftTerm
import SwiftUI

@available(macOS 15.0, *)
@MainActor
final class TerminalController: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case live
        case reconnecting(attempt: Int)
        case closed(reason: String?)
    }

    @Published private(set) var state: State = .idle
    /// The way the live shell reached the server
    @Published private(set) var route: TerminalEndpoint.Kind?
    /// Every route failed to answer
    @Published private(set) var noRouteAnswered = false
    let profile: TerminalProfile
    let deployment: Deployment

    /// The emulator, once SwiftUI has made one
    weak var view: SwiftTerm.TerminalView?

    private var session: TerminalSession?
    private var demoShell: DemoShell?
    private var reader: Task<Void, Never>?
    private var redial: Task<Void, Never>?
    /// Output that arrived before the emulator existed
    private var pending = [UInt8]()
    private var last: Dial?
    private var size = (columns: 80, rows: 24)

    /// Pauses between automatic reconnects
    static let reconnectPauses: [Duration] = [.seconds(1), .seconds(3), .seconds(8), .seconds(15)]

    private struct Dial {
        let target: TerminalEndpointBuilder.Target
        let login: TerminalLogin
        let onPinHostKey: @Sendable (String, String) -> Void
    }

    init(deployment: Deployment, profile: TerminalProfile) {
        self.deployment = deployment
        self.profile = profile
    }

    func attach(_ view: SwiftTerm.TerminalView) {
        self.view = view
        if !pending.isEmpty {
            view.feed(byteArray: pending[...])
            pending.removeAll()
        }
    }

    var isBusy: Bool {
        switch state {
        case .connecting, .live, .reconnecting: return true
        case .idle, .closed: return false
        }
    }

    func connect(target: TerminalEndpointBuilder.Target, login: TerminalLogin,
                 columns: Int, rows: Int,
                 onPinHostKey: @escaping @Sendable (String, String) -> Void) async {
        guard state != .live, state != .connecting else { return }
        redial?.cancel()
        redial = nil
        size = (columns, rows)
        last = Dial(target: target, login: login, onPinHostKey: onPinHostKey)
        state = .connecting
        if let reason = await open() {
            state = .closed(reason: reason)
        }
    }

    /// Opens a session over the stored routes, or why not
    private func open() async -> String? {
        guard let last else { return nil }
        noRouteAnswered = false
        let session = TerminalSession(routes: last.target.routes, login: last.login,
                                      onPinHostKey: last.onPinHostKey)
        self.session = session
        do {
            let events = try await session.start(columns: size.columns, rows: size.rows)
            guard self.session === session else {
                await session.close()
                return nil
            }
            if let used = await session.connectedRoute {
                route = used.kind
                TerminalEndpointBuilder.remember(used, key: last.target.memoryKey)
            }
            state = .live
            if profile.keepAliveWithTmux {
                send(ArraySlice(Array(TerminalTmux.launchCommand(profileID: profile.id).utf8)))
            }
            if let script = TerminalScriptQueue.shared.take(for: deployment.id) {
                send(ArraySlice(Array(script.utf8)))
            }
            reader = Task { [weak self] in
                for await event in events {
                    self?.handle(event, from: session)
                }
            }
            return nil
        } catch {
            if self.session === session { self.session = nil }
            noRouteAnswered = error is TerminalRoutesFailed || Self.isUnreachable(error)
            return Self.describe(error, routes: last.target.routes)
        }
    }

    /// Resolves the routes and login, then dials; returns the routes
    @discardableResult
    func startResolved() async -> [TerminalEndpoint] {
        if DemoFleet.covers(deployment) {
            startDemo()
            return []
        }
        guard LicenseStore.isUnlocked else {
            reportFailure(LicenseGate.message(for: LicenseGate.reason))
            LicensePrompt.shared.allow()
            return []
        }
        let deployment = deployment
        let profile = profile
        let resolved: Result<(TerminalEndpointBuilder.Target, TerminalLogin), Error> =
            await Task.detached {
                do {
                    let target = try TerminalEndpointBuilder.target(for: deployment,
                                                                    nodeID: profile.nodeID)
                    let login = try TerminalEndpointBuilder.login(for: profile,
                                                                  deployment: deployment)
                    return .success((target, login))
                } catch {
                    return .failure(error)
                }
            }.value
        switch resolved {
        case .failure(let error):
            reportFailure(error.localizedDescription)
            return []
        case .success(let (target, login)):
            await connect(target: target, login: login, columns: size.columns, rows: size.rows,
                          onPinHostKey: target.pinner(deploymentID: deployment.id))
            return target.routes
        }
    }

    func reportFailure(_ reason: String) {
        state = .closed(reason: reason)
    }

    /// Opens the pretend shell of a demo server
    private func startDemo() {
        let shell = DemoShell(user: profile.username, host: deployment.name)
        state = .live
        feed(Array(shell.banner.utf8))
        demoShell = shell
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        if var shell = demoShell {
            let shown = shell.input(bytes)
            demoShell = shell
            feed(Array(shown.utf8))
            return
        }
        guard let session else { return }
        let data = Data(bytes)
        Task { await session.send(data) }
    }

    func resize(columns: Int, rows: Int) {
        size = (columns, rows)
        guard let session else { return }
        Task { await session.resize(columns: columns, rows: rows) }
    }

    func disconnect() {
        redial?.cancel()
        redial = nil
        reader?.cancel()
        reader = nil
        let session = self.session
        self.session = nil
        demoShell = nil
        route = nil
        state = .closed(reason: nil)
        Task { await session?.close() }
    }

    private func handle(_ event: TerminalEvent, from source: TerminalSession) {
        guard source === session else { return }
        switch event {
        case .output(let data):
            feed([UInt8](data))
        case .closed(let reason):
            session = nil
            route = nil
            if let reason {
                reconnect(after: reason)
            } else {
                state = .closed(reason: nil)
            }
        }
    }

    /// A dropped link comes back without a tap
    private func reconnect(after reason: String) {
        redial?.cancel()
        notice(UIL10n.string("Connection lost. Reconnecting…"))
        redial = Task { [weak self] in
            for (index, pause) in Self.reconnectPauses.enumerated() {
                guard let self, !Task.isCancelled else { return }
                self.state = .reconnecting(attempt: index + 1)
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled else { return }
                if await self.open() == nil {
                    self.notice(UIL10n.string("Reconnected. This is a new shell."))
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.state = .closed(reason: reason)
        }
    }

    private func feed(_ bytes: [UInt8]) {
        if let view {
            view.feed(byteArray: bytes[...])
        } else {
            pending.append(contentsOf: bytes)
        }
    }

    /// A dim line in the emulator, outside the shell
    private func notice(_ text: String) {
        feed([UInt8]("\r\n\u{1B}[2m[\(text)]\u{1B}[0m\r\n".utf8))
    }

    #if DEBUG
    /// Feed the emulator canned output instead of connecting
    func feedDebug(_ text: String) {
        state = .live
        feed([UInt8](Data(text.utf8)))
    }
    #endif

    nonisolated private static func isUnreachable(_ error: Error) -> Bool {
        if case .connectionFailed = error as? ServerControlError { return true }
        return false
    }

    nonisolated static func describe(_ error: Error, routes: [TerminalEndpoint]) -> String {
        if let failed = error as? TerminalRoutesFailed {
            return failed.attempts.map { attempt(on: $0.route, failed: $0.reason) }.joined(separator: "\n")
        }
        let reason = (error as? ServerControlError)?.localizedDescription ?? String(describing: error)
        guard routes.count == 1, let only = routes.first, isUnreachable(error) else { return reason }
        let line = attempt(on: only, failed: reason)
        guard only.hops.isEmpty, TerminalVPNOffer.isPrivate(only.host) else { return line }
        return line + "\n" + UIL10n.string("Only the direct way was tried. To reach a machine in a home network through a server, choose it under “Through a server” in this connection's settings.")
    }

    /// One tried way and why it failed
    nonisolated private static func attempt(on route: TerminalEndpoint, failed reason: String) -> String {
        UIL10n.string("%@ (%@): %@", TerminalVPNOffer.title(of: route.kind), route.summary, reason)
    }
}
