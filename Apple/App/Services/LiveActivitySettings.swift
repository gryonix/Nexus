import Combine
import Foundation

/// Whether the VPN session shows as a Live Activity
@MainActor
final class LiveActivitySettings: ObservableObject {
    static let shared = LiveActivitySettings()

    @Published var showsVPNSession: Bool {
        didSet {
            guard showsVPNSession != oldValue else { return }
            defaults.set(showsVPNSession, forKey: Self.vpnSessionKey)
            onChange?(showsVPNSession)
        }
    }

    /// Called after the switch flips
    var onChange: ((Bool) -> Void)?

    @Published var vpnIslandStyle: VPNIslandStyle {
        didSet {
            guard vpnIslandStyle != oldValue else { return }
            vpnIslandStyle.save(defaults)
            onStyleChange?()
        }
    }

    /// Called after the island's look changed
    var onStyleChange: (() -> Void)?

    /// Shows operation cards on the island and lock screen
    @Published var showsOperations: Bool {
        didSet {
            guard showsOperations != oldValue else { return }
            defaults.set(showsOperations, forKey: Self.operationsKey)
            onOperationsChange?()
        }
    }

    /// Kinds of operation the cards leave out
    @Published var hiddenOperationKinds: Set<OperationKind> {
        didSet {
            guard hiddenOperationKinds != oldValue else { return }
            defaults.set(hiddenOperationKinds.map(\.rawValue).sorted(), forKey: Self.hiddenKindsKey)
            onOperationsChange?()
        }
    }

    /// Called after the operation-card switches change
    var onOperationsChange: (() -> Void)?

    /// Kinds the servers must not start as cards here
    var refusedKinds: [String] {
        showsOperations ? hiddenOperationKinds.map(\.rawValue).sorted() : OperationKind.allCases.map(\.rawValue)
    }

    /// Whether a card of this kind may show
    func shows(_ kind: OperationKind) -> Bool {
        showsOperations && !hiddenOperationKinds.contains(kind)
    }

    private let defaults: UserDefaults
    static let vpnSessionKey = "liveActivity.vpnSession"
    static let operationsKey = "liveActivity.operations"
    static let hiddenKindsKey = "liveActivity.hiddenOperationKinds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showsVPNSession = defaults.object(forKey: Self.vpnSessionKey) as? Bool ?? true
        self.vpnIslandStyle = VPNIslandStyle.current(defaults)
        self.showsOperations = defaults.object(forKey: Self.operationsKey) as? Bool ?? true
        let hidden = defaults.stringArray(forKey: Self.hiddenKindsKey) ?? []
        self.hiddenOperationKinds = Set(hidden.compactMap(OperationKind.init(rawValue:)))
    }
}

/// Server operation kinds, named as the agent names them
enum OperationKind: String, CaseIterable, Sendable {
    case install, update, backup, restore, move, removal, other
}
