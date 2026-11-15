import SwiftUI

/// A tab of the TV app
enum TVTab: String, CaseIterable, Identifiable {
    case servers, vpn, metrics, containers

    var id: String { rawValue }

    /// The phone's matching section, for its title and icon
    var appTab: AppTab {
        switch self {
        case .servers: return .servers
        case .vpn: return .vpn
        case .metrics: return .metrics
        case .containers: return .containers
        }
    }
}

@MainActor
final class TVTabSettings: ObservableObject {
    static let shared = TVTabSettings()

    private enum Keys {
        static let order = "tv.tabs.order"
        static let hidden = "tv.tabs.hidden"
        static let labels = "tv.tabs.labels"
    }

    @Published var order: [TVTab] { didSet { defaults.set(order.map(\.rawValue), forKey: Keys.order) } }
    @Published var hidden: Set<TVTab> { didSet { defaults.set(hidden.map(\.rawValue), forKey: Keys.hidden) } }
    @Published var labels: SectionLabels { didSet { defaults.set(labels.rawValue, forKey: Keys.labels) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.array(forKey: Keys.order) as? [String] ?? []).compactMap(TVTab.init(rawValue:))
        order = stored + TVTab.allCases.filter { !stored.contains($0) }
        hidden = Set((defaults.array(forKey: Keys.hidden) as? [String] ?? []).compactMap(TVTab.init(rawValue:)))
        labels = defaults.string(forKey: Keys.labels).flatMap(SectionLabels.init(rawValue:)) ?? .text
    }

    var visible: [TVTab] { order.filter { !hidden.contains($0) } }

    /// Changes whenever the tab bar must be rebuilt
    var layoutKey: String { visible.map(\.rawValue).joined(separator: ",") }

    func move(_ tab: TVTab, by offset: Int) {
        guard let index = order.firstIndex(of: tab) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    func setVisible(_ visible: Bool, for tab: TVTab) {
        if visible { hidden.remove(tab) } else if self.visible.count > 1 { hidden.insert(tab) }
    }
}
