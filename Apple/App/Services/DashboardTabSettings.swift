import Foundation
import SwiftUI

@MainActor
final class DashboardTabSettings: ObservableObject {
    static let shared = DashboardTabSettings()

    private enum Keys {
        static let order = "dashboard.segmentOrder"
        static let hidden = "dashboard.segmentHidden"
        static let start = "dashboard.segmentStart"
    }

    @Published var order: [DashboardTab] { didSet { persistOrder() } }

    @Published private var hidden: [String: Set<DashboardTab>] { didSet { persistHidden() } }

    @Published var startTab: DashboardTab { didSet { defaults.set(startTab.rawValue, forKey: Keys.start) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.array(forKey: Keys.order) as? [String] ?? [])
            .compactMap(DashboardTab.init(rawValue:))
        order = Self.reconcile(stored: stored)
        let storedHidden = defaults.dictionary(forKey: Keys.hidden) as? [String: [String]] ?? [:]
        hidden = storedHidden.mapValues { Set($0.compactMap(DashboardTab.init(rawValue:))) }
        startTab = defaults.string(forKey: Keys.start).flatMap(DashboardTab.init(rawValue:)) ?? .general
    }

    func startTab(among available: [DashboardTab], on deploymentID: UUID) -> DashboardTab {
        let shown = ordered(available, on: deploymentID)
        return shown.contains(startTab) ? startTab : (shown.first ?? .general)
    }

    /// Is this segment shown on this server?
    func isVisible(_ tab: DashboardTab, on deploymentID: UUID) -> Bool {
        !(hidden[deploymentID.uuidString]?.contains(tab) ?? false)
    }

    /// Turn a segment off (or back on) for ONE server
    func setVisible(_ visible: Bool, for tab: DashboardTab, on deploymentID: UUID,
                    available: [DashboardTab]) {
        let key = deploymentID.uuidString
        var set = hidden[key] ?? []
        if visible {
            set.remove(tab)
        } else {
            guard available.contains(where: { $0 != tab && !set.contains($0) }) else { return }
            set.insert(tab)
        }
        if set.isEmpty { hidden.removeValue(forKey: key) } else { hidden[key] = set }
    }

    func canHide(_ tab: DashboardTab, on deploymentID: UUID, available: [DashboardTab]) -> Bool {
        guard isVisible(tab, on: deploymentID) else { return true }
        return available.contains { $0 != tab && isVisible($0, on: deploymentID) }
    }

    func forget(deploymentID: UUID) {
        hidden.removeValue(forKey: deploymentID.uuidString)
    }

    static func reconcile(stored: [DashboardTab]) -> [DashboardTab] {
        guard !stored.isEmpty else { return DashboardTab.allCases }
        var result = stored.filter { DashboardTab(rawValue: $0.rawValue) != nil }
        for tab in DashboardTab.allCases where !result.contains(tab) {
            guard let canonical = DashboardTab.allCases.firstIndex(of: tab) else { continue }
            let preceding = DashboardTab.allCases[..<canonical].last { result.contains($0) }
            if let preceding, let index = result.firstIndex(of: preceding) {
                result.insert(tab, at: index + 1)
            } else {
                result.insert(tab, at: 0)
            }
        }
        return result
    }

    func ordered(_ available: [DashboardTab]) -> [DashboardTab] {
        let mine = order.filter(available.contains)
        return mine + available.filter { !mine.contains($0) }
    }

    func ordered(_ available: [DashboardTab], on deploymentID: UUID) -> [DashboardTab] {
        let shown = ordered(available).filter { isVisible($0, on: deploymentID) }
        return shown.isEmpty ? ordered(available) : shown
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    private func persistOrder() {
        defaults.set(order.map(\.rawValue), forKey: Keys.order)
    }

    private func persistHidden() {
        let plain = hidden.mapValues { $0.map(\.rawValue).sorted() }
        if plain.isEmpty {
            defaults.removeObject(forKey: Keys.hidden)
        } else {
            defaults.set(plain, forKey: Keys.hidden)
        }
    }
}
