import Foundation
import ServiceCatalog
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A top-level section of the app
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case servers
    case metrics
    case containers
    case vpn
    case terminal
    case configurator
    case settings

    var id: String { rawValue }

    /// The English source string, which is also the catalog key
    var titleKey: String {
        switch self {
        case .servers: return "Servers"
        case .containers: return "Containers"
        case .metrics: return "Metrics"
        case .vpn: return "VPN"
        case .terminal: return "Terminal"
        case .configurator: return "Configurator"
        case .settings: return "Settings"
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }

    /// Resolved through the app's own bundle lookup, for UIKit callers
    var localizedTitle: String { UIL10n.string(titleKey) }

    var systemImage: String {
        switch self {
        case .servers: return "server.rack"
        case .containers: return "shippingbox"
        case .metrics: return "chart.xyaxis.line"
        case .vpn: return "lock.shield"
        case .terminal: return "apple.terminal"
        case .configurator: return "doc.badge.gearshape"
        case .settings: return "gearshape"
        }
    }

    /// The section's picture, as ONE property
    var icon: Image {
        switch self {
        case .vpn: return Image("TabIconLogo")
        case .servers, .containers, .metrics, .terminal, .configurator, .settings:
            return Image(systemName: systemImage)
        }
    }

    func icon(tunnelActive: Bool) -> Image {
        switch self {
        case .vpn: return Image(tunnelActive ? "TabIconLogo" : "TabIconGlobe")
        case .servers, .containers, .metrics, .terminal, .configurator, .settings:
            return icon
        }
    }

    /// `icon`, drawn hollow — the plain symbol, never its `.fill` variant
    @ViewBuilder
    func barIcon(tunnelActive: Bool) -> some View {
        icon(tunnelActive: tunnelActive)
            .environment(\.symbolVariants, .none)
    }

    #if os(iOS)
    var uiIcon: UIImage? {
        switch self {
        case .vpn: return UIImage(named: "TabIconLogo")?.withRenderingMode(.alwaysTemplate)
        case .servers, .containers, .metrics, .terminal, .configurator, .settings:
            return UIImage(systemName: systemImage)
        }
    }

    func barIconName(tunnelActive: Bool) -> String {
        switch self {
        case .vpn: return tunnelActive ? "TabIconLogo" : "TabIconGlobe"
        case .servers, .containers, .metrics, .terminal, .configurator, .settings:
            return systemImage
        }
    }
    #endif

    var canBeHidden: Bool { self != .settings }
}

enum BarStyle: String, CaseIterable, Identifiable, Hashable {
    case custom
    case system

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .custom: return "gryonixNexus"
        case .system: return "System"
        }
    }
}

@MainActor
final class TabBarSettings: ObservableObject {
    static let shared = TabBarSettings()

    private enum Keys {
        static let order = "tabs.order"
        static let orderRevision = "tabs.orderRevision"
        static let hidden = "tabs.hidden"
        static let start = "tabs.start"
        static let sitesCollapsible = "dashboard.sitesCollapsible"
        static let sitesExpanded = "dashboard.sitesExpanded"
        static let groupServicesByCategory = "dashboard.groupServicesByCategory"
        static let barStyle = "tabs.barStyle"
        static let sectionStripStyle = "dashboard.stripStyle"
        static let groupStripStyle = "fleet.groupsStyle"
        static let periodStripStyle = "metrics.periodStyle"
    }

    @Published var order: [AppTab] { didSet { persistOrder() } }
    @Published var hidden: Set<AppTab> { didSet { persistHidden() } }
    @Published var startTab: AppTab { didSet { defaults.set(startTab.rawValue, forKey: Keys.start) } }

    @Published var barStyle: BarStyle { didSet { defaults.set(barStyle.rawValue, forKey: Keys.barStyle) } }

    @Published var sectionStripStyle: BarStyle {
        didSet { defaults.set(sectionStripStyle.rawValue, forKey: Keys.sectionStripStyle) }
    }

    @Published var groupStripStyle: BarStyle {
        didSet { defaults.set(groupStripStyle.rawValue, forKey: Keys.groupStripStyle) }
    }

    /// The metrics-history period picker
    @Published var periodStripStyle: BarStyle {
        didSet { defaults.set(periodStripStyle.rawValue, forKey: Keys.periodStripStyle) }
    }

    /// Whether the dashboard's "Sites" section can be folded away
    @Published var sitesCollapsible: Bool {
        didSet { defaults.set(sitesCollapsible, forKey: Keys.sitesCollapsible) }
    }

    /// Remembered fold state, so the choice survives leaving the dashboard
    @Published var sitesExpanded: Bool {
        didSet { defaults.set(sitesExpanded, forKey: Keys.sitesExpanded) }
    }

    @Published var groupServicesByCategoryOverride: Bool? {
        didSet {
            if let value = groupServicesByCategoryOverride {
                defaults.set(value, forKey: Keys.groupServicesByCategory)
            } else {
                defaults.removeObject(forKey: Keys.groupServicesByCategory)
            }
        }
    }

    func groupsServices(in services: [ServiceID]) -> Bool {
        groupServicesByCategoryOverride ?? Self.aShelfHoldsSeveral(services)
    }

    /// Whether any category would hold two or more ROWS
    nonisolated static func aShelfHoldsSeveral(_ services: [ServiceID]) -> Bool {
        var seen: Set<ServiceCategory> = []
        for id in services {
            guard let category = ServiceRegistry.service(id)?.displayCategory else { continue }
            if !seen.insert(category).inserted { return true }
        }
        return false
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.array(forKey: Keys.order) as? [String] ?? [])
            .compactMap(AppTab.init(rawValue:))
        order = Self.reconcile(stored: stored, defaults: defaults)
        hidden = Set((defaults.array(forKey: Keys.hidden) as? [String] ?? [])
            .compactMap(AppTab.init(rawValue:))
            .filter(\.canBeHidden))
        startTab = (defaults.string(forKey: Keys.start).flatMap(AppTab.init(rawValue:))) ?? .servers
        sitesCollapsible = defaults.object(forKey: Keys.sitesCollapsible) as? Bool ?? true
        sitesExpanded = defaults.object(forKey: Keys.sitesExpanded) as? Bool ?? true
        groupServicesByCategoryOverride = defaults.object(forKey: Keys.groupServicesByCategory) as? Bool
        Self.startFreshInstallOnSystemBars(defaults)
        let storedBarStyle = defaults.string(forKey: Keys.barStyle).flatMap(BarStyle.init(rawValue:)) ?? .custom
        let forced = Self.forcedStyle
        barStyle = forced ?? storedBarStyle
        sectionStripStyle = forced ?? defaults.string(forKey: Keys.sectionStripStyle)
            .flatMap(BarStyle.init(rawValue:)) ?? storedBarStyle
        groupStripStyle = forced ?? defaults.string(forKey: Keys.groupStripStyle)
            .flatMap(BarStyle.init(rawValue:)) ?? storedBarStyle
        periodStripStyle = forced ?? defaults.string(forKey: Keys.periodStripStyle)
            .flatMap(BarStyle.init(rawValue:)) ?? storedBarStyle
    }

    /// A fresh install starts on Apple's own bars
    private static func startFreshInstallOnSystemBars(_ defaults: UserDefaults) {
        guard forcedStyle == nil, defaults.string(forKey: Keys.barStyle) == nil,
              !WelcomeState.hasBeenShown(in: defaults) else { return }
        for key in [Keys.barStyle, Keys.sectionStripStyle, Keys.groupStripStyle,
                    Keys.periodStripStyle] {
            defaults.set(BarStyle.system.rawValue, forKey: key)
        }
    }

    #if DEBUG
    /// Forgets every bar style, as on a new install
    nonisolated static func forgetBarStyles(_ defaults: UserDefaults = .standard) {
        for key in [Keys.barStyle, Keys.sectionStripStyle, Keys.groupStripStyle,
                    Keys.periodStripStyle] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif

    private static var forcedStyle: BarStyle? {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_BAR_STYLE"]
            .flatMap(BarStyle.init(rawValue:))
        #else
        nil
        #endif
    }

    static func reconcile(stored: [AppTab], defaults: UserDefaults) -> [AppTab] {
        guard !stored.isEmpty else { return AppTab.allCases }
        if Self.shippedDefaults.contains(stored) {
            defaults.set(AppTab.allCases.map(\.rawValue), forKey: Keys.order)
            return AppTab.allCases
        }
        var result = stored
        for tab in AppTab.allCases where !result.contains(tab) {
            guard let canonical = AppTab.allCases.firstIndex(of: tab) else { continue }
            let preceding = AppTab.allCases[..<canonical].last { result.contains($0) }
            if let preceding, let index = result.firstIndex(of: preceding) {
                result.insert(tab, at: index + 1)
            } else {
                result.insert(tab, at: 0)
            }
        }
        return result
    }

    /// Every order this app has ever shipped as its default
    private static let shippedDefaults: [[AppTab]] = [
        [.servers, .metrics, .configurator, .settings],
        [.servers, .metrics, .configurator, .vpn, .settings],
        [.servers, .metrics, .configurator, .settings, .vpn],
        [.servers, .metrics, .vpn, .configurator, .settings],
        AppTab.allCases
    ]

    /// The sections to actually show, in the user's order
    var visibleTabs: [AppTab] {
        let shown = order.filter { !hidden.contains($0) }
        return shown.isEmpty ? [.settings] : shown
    }

    var effectiveStartTab: AppTab {
        visibleTabs.contains(startTab) ? startTab : (visibleTabs.first ?? .settings)
    }

    func isVisible(_ tab: AppTab) -> Bool { !hidden.contains(tab) }

    func setVisible(_ visible: Bool, for tab: AppTab) {
        guard tab.canBeHidden else { return }
        if visible { hidden.remove(tab) } else { hidden.insert(tab) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    func moveUp(_ tab: AppTab) {
        guard let index = order.firstIndex(of: tab), index > 0 else { return }
        order.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    func moveDown(_ tab: AppTab) {
        guard let index = order.firstIndex(of: tab), index < order.count - 1 else { return }
        order.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }

    func canMoveUp(_ tab: AppTab) -> Bool {
        (order.firstIndex(of: tab) ?? 0) > 0
    }

    func canMoveDown(_ tab: AppTab) -> Bool {
        guard let index = order.firstIndex(of: tab) else { return false }
        return index < order.count - 1
    }

    private func persistOrder() { defaults.set(order.map(\.rawValue), forKey: Keys.order) }
    private func persistHidden() { defaults.set(hidden.map(\.rawValue).sorted(), forKey: Keys.hidden) }
}
