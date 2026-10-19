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
        case closed(reason: String?)
    }

    @Published private(set) var state: State = .idle
    let profile: TerminalProfile
    let deployment: Deployment

    /// The emulator, once SwiftUI has made one
    weak var view: SwiftTerm.TerminalView?

    private var session: TerminalSession?
    private var reader: Task<Void, Never>?
    /// Output that arrived before the emulator existed
    private var pending = [UInt8]()

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

    func connect(endpoint: TerminalEndpoint, login: TerminalLogin,
                 columns: Int, rows: Int,
                 onPinHostKey: @escaping @Sendable (String, String) -> Void) async {
        guard state != .live, state != .connecting else { return }
        state = .connecting
        let session = TerminalSession(endpoint: endpoint, login: login,
                                      onPinHostKey: onPinHostKey)
        self.session = session
        do {
            let events = try await session.start(columns: columns, rows: rows)
            state = .live
            reader = Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
            }
        } catch {
            state = .closed(reason: Self.describe(error))
            self.session = nil
        }
    }

    func reportFailure(_ reason: String) {
        state = .closed(reason: reason)
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        guard let session else { return }
        let data = Data(bytes)
        Task { await session.send(data) }
    }

    func resize(columns: Int, rows: Int) {
        guard let session else { return }
        Task { await session.resize(columns: columns, rows: rows) }
    }

    func disconnect() {
        reader?.cancel()
        reader = nil
        let session = self.session
        self.session = nil
        state = .closed(reason: nil)
        Task { await session?.close() }
    }

    private func handle(_ event: TerminalEvent) {
        switch event {
        case .output(let data):
            let bytes = [UInt8](data)
            if let view {
                view.feed(byteArray: bytes[...])
            } else {
                pending.append(contentsOf: bytes)
            }
        case .closed(let reason):
            state = .closed(reason: reason)
            session = nil
        }
    }

    #if DEBUG
    /// Feed the emulator canned output instead of connecting
    func feedDebug(_ text: String) {
        state = .live
        let bytes = [UInt8](Data(text.utf8))
        if let view {
            view.feed(byteArray: bytes[...])
        } else {
            pending.append(contentsOf: bytes)
        }
    }
    #endif

    private static func describe(_ error: Error) -> String {
        if let error = error as? ServerControlError {
            return error.localizedDescription
        }
        return String(describing: error)
    }
}
