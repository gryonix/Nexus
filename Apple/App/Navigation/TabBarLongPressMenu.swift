#if os(iOS)
import ServerControl
import SwiftUI
import UIKit

struct TabBarLongPressMenu: ViewModifier {
    @ObservedObject private var tabs = TabBarSettings.shared
    @State private var installer = MenuInstaller()

    func body(content: Content) -> some View {
        content.task {
            for _ in 0..<40 {
                if installer.install() {
                    await Self.openForProbe()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func openForProbe() async {
        guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TABBAR_MENU"],
              let bar = MenuInstaller.tabBar(),
              let presenter = MenuInstaller.presenter(on: bar) else { return }
        try? await Task.sleep(for: .milliseconds(900))
        for field in raw.split(separator: ",") {
            if field.hasPrefix("t"), let index = Int(field.dropFirst()) {
                let slots = TabBarMenuPresenter.tabSlots(in: bar)
                if index < slots.count, let title = slots[index].title,
                   let tab = TabBarMenuPresenter.tab(named: title) {
                    AppNavigator.shared.show(tab)
                    try? await Task.sleep(for: .milliseconds(900))
                }
                continue
            }
            guard let index = Int(field) else { continue }
            let slots = TabBarMenuPresenter.tabSlots(in: bar)
            guard index >= 0, index < slots.count else { continue }
            presenter.present(in: bar, at: CGPoint(x: slots[index].frame.midX,
                                                   y: slots[index].frame.midY))
            try? await Task.sleep(for: .milliseconds(700))
            Self.reportPlacement(index: index, slot: slots[index], bar: bar)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func reportPlacement(index: Int, slot: TabBarMenuPresenter.Slot,
                                        bar: UITabBar) {
        let inScreen = bar.convert(slot.frame, to: nil)
        var menu: CGRect?
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var queue: [UIView] = [window]
                while !queue.isEmpty {
                    let view = queue.removeFirst()
                    if String(describing: type(of: view)) == "_UIContextMenuView" {
                        menu = view.convert(view.bounds, to: nil)
                    }
                    queue.append(contentsOf: view.subviews)
                }
            }
        }
        let held = "\(Int(inScreen.minX))…\(Int(inScreen.maxX))"
        let landed = menu.map { "\(Int($0.minX))…\(Int($0.maxX)) up to \(Int($0.maxY))" } ?? "-"
        print("PROBE tab=\(index) \(slot.title ?? "-") held=\(held) menu=\(landed)")
    }
}

/// Puts the menu's gesture on the bar
@MainActor
final class MenuInstaller {
    /// Where the bar keeps its presenter
    private enum Key { nonisolated(unsafe) static var presenter: UInt8 = 0 }

    @discardableResult
    func install() -> Bool {
        guard let bar = Self.tabBar() else { return false }
        return install(on: bar)
    }

    @discardableResult
    func install(on bar: UITabBar) -> Bool {
        guard #available(iOS 17.4, *) else { return true }
        if Self.isInstalled(on: bar) { return true }
        let presenter = TabBarMenuPresenter()
        objc_setAssociatedObject(bar, &Key.presenter, presenter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter.attach(to: bar)
        return true
    }

    static func isInstalled(on bar: UITabBar) -> Bool {
        objc_getAssociatedObject(bar, &Key.presenter) is TabBarMenuPresenter
    }

    static func presenter(on bar: UITabBar) -> TabBarMenuPresenter? {
        objc_getAssociatedObject(bar, &Key.presenter) as? TabBarMenuPresenter
    }

    static func tabBar() -> UITabBar? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            .flatMap { Self.firstTabBar(in: $0) }
    }

    private static func firstTabBar(in root: UIView) -> UITabBar? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let bar = view as? UITabBar { return bar }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

/// Opens the menu of whichever tab is being held
@MainActor
final class TabBarMenuPresenter: NSObject, UIGestureRecognizerDelegate {
    private var anchor: AnchorButton?

    private func makeAnchor() -> AnchorButton {
        let button = AnchorButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        return button
    }

    /// Puts the gesture on the bar
    func attach(to bar: UITabBar) {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress))
        press.minimumPressDuration = 0.35
        press.delegate = self
        bar.addGestureRecognizer(press)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let bar = gesture.view as? UITabBar else { return }
        present(in: bar, at: gesture.location(in: bar))
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    /// Opens the menu for the tab under `point`
    func present(in bar: UITabBar, at point: CGPoint) {
        let slots = Self.tabSlots(in: bar)
        let tab = Self.tab(at: point, slots: slots)
        anchor?.removeFromSuperview()
        let button = makeAnchor()
        button.frame = Self.anchorFrame(in: bar.bounds, slots: slots.map(\.frame),
                                        pressedAt: point)
        bar.addSubview(button)
        anchor = button
        button.menu = Self.menu(for: tab)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if #available(iOS 17.4, *) { button.performPrimaryAction() }
    }

    static func anchorFrame(in bounds: CGRect, slots: [CGRect],
                            pressedAt point: CGPoint?) -> CGRect {
        let column: (x: CGFloat, width: CGFloat)
        if let point, let index = slotIndex(at: point.x, slots: slots) {
            column = (slots[index].minX, slots[index].width)
        } else {
            let side: CGFloat = 44
            let centre = point?.x ?? bounds.midX
            let x = min(max(centre, bounds.minX + side / 2), bounds.maxX - side / 2)
            column = (x - side / 2, side)
        }
        let lift: CGFloat = 14
        return CGRect(x: column.x, y: bounds.minY - lift, width: column.width, height: 1)
    }

    private static func menu(for tab: AppTab?) -> UIMenu {
        guard let tab else { return UIMenu(children: [barVisibility()]) }
        return UIMenu(title: tab.localizedTitle,
                      children: actions(for: tab) + [barVisibility()])
    }

    static func customBarMenu(for tab: AppTab) -> UIMenu { menu(for: tab) }

    /// What each section offers
    private static func actions(for tab: AppTab) -> [UIMenuElement] {
        let fleet = fleet()
        switch tab {
        case .servers:
            let open = servers(fleet) { AppNavigator.shared.openServer($0.id) }
            return [open, UIMenu(title: "", options: .displayInline, children: [
                action("Add server", "plus") { AppNavigator.shared.askServers(.add) },
                action("Import server", "square.and.arrow.down") {
                    AppNavigator.shared.askServers(.importServer)
                },
                action("Export servers", "square.and.arrow.up") {
                    AppNavigator.shared.askServers(.export)
                },
            ])]
        case .metrics:
            return [servers(fleet) { AppNavigator.shared.showServer($0.id, in: .metrics) }]
        case .configurator:
            return [UIMenu(title: "", options: .displayInline,
                           children: ScenarioOption.all.map { option in
                               action(option.titleKey, option.systemImage) {
                                   AppNavigator.shared.showScenario(option.id)
                               }
                           })]
        case .settings:
            return [UIMenu(title: "", options: .displayInline, children: [
                action("Appearance", "paintbrush") {
                    AppNavigator.shared.showSettingsPage(.appearance)
                },
                action("Sections", "square.grid.2x2") {
                    AppNavigator.shared.showSettingsPage(.sections)
                },
            ])]
        case .vpn:
            return [servers(VPNSectionView.manageable(in: fleet)) {
                AppNavigator.shared.showServer($0.id, in: .vpn)
            }]
        case .containers:
            return [servers(fleet) { AppNavigator.shared.showServer($0.id, in: .containers) }]
        case .terminal:
            var groups: [UIMenuElement] = [
                servers(fleet) { AppNavigator.shared.showServer($0.id, in: .terminal) },
            ]
            let direct = (try? TerminalDirectHostStore().load()) ?? []
            if !direct.isEmpty {
                groups.append(UIMenu(title: UIL10n.string("Other connections"),
                                     image: UIImage(systemName: "network"),
                                     children: direct.prefix(6).map { host in
                                         UIAction(title: host.title,
                                                  image: UIImage(systemName: "terminal")) { _ in
                                             MainActor.assumeIsolated {
                                                 AppNavigator.shared.openTerminalHost(host.id)
                                             }
                                         }
                                     }))
            }
            return groups
        }
    }

    private static func fleet() -> [Deployment] {
        let stored = (try? FileDeploymentStore().load()) ?? []
        let real = stored.filter { !DemoServer.isDemo($0) }
        return real.isEmpty && DemoServer.isEnabled ? DemoServer.deployments() : real
    }

    /// One inline group of servers
    private static func servers(_ fleet: [Deployment],
                                _ open: @escaping (Deployment) -> Void) -> UIMenu {
        let items = fleet.prefix(6).map { deployment in
            UIAction(title: deployment.name,
                     image: UIImage(systemName: deployment.iconSymbol ?? "server.rack")) { _ in
                MainActor.assumeIsolated { open(deployment) }
            }
        }
        return UIMenu(title: "", options: .displayInline, children: Array(items))
    }

    private static func action(_ title: String, _ symbol: String,
                               _ run: @escaping () -> Void) -> UIAction {
        UIAction(title: UIL10n.string(title), image: UIImage(systemName: symbol)) { _ in
            MainActor.assumeIsolated { run() }
        }
    }

    /// Which sections the bar carries
    private static func barVisibility() -> UIMenu {
        let tabs = TabBarSettings.shared
        let sections = tabs.order.map { tab -> UIAction in
            let on = ShellSectionVisibility.isOnBar(tab, tabs: tabs)
            let item = UIAction(title: tab.localizedTitle,
                                image: tab.uiIcon,
                                state: on ? .on : .off) { _ in
                MainActor.assumeIsolated {
                    ShellSectionVisibility.setOnBar(!on, for: tab, tabs: TabBarSettings.shared)
                }
            }
            if !tab.canBeHidden { item.attributes = [.disabled] }
            return item
        }
        return UIMenu(title: UIL10n.string("Show on the bar"),
                      image: UIImage(systemName: "rectangle.bottomthird.inset.filled"),
                      children: sections)
    }

    static func barSections() -> [AppTab] {
        let tabs = TabBarSettings.shared
        let defaults = UserDefaults.standard
        let visible = ShellSections.visible(
            order: tabs.visibleTabs,
            metricsRaw: defaults.string(forKey: MetricsDisplaySettings.placementKey)
                ?? MetricsPlacement.both.rawValue,
            vpnRaw: defaults.string(forKey: VPNDisplaySettings.placementKey)
                ?? VPNPlacement.both.rawValue,
            containersRaw: defaults.string(forKey: ContainersDisplaySettings.placementKey)
                ?? ContainersPlacement.server.rawValue,
            terminalRaw: defaults.string(forKey: TerminalDisplaySettings.placementKey)
                ?? TerminalPlacement.server.rawValue)
        return ShellSections.onBar(visible)
    }

    struct Slot {
        let frame: CGRect
        let title: String?
    }

    static func tabSlots(in bar: UITabBar) -> [Slot] {
        var groups: [ObjectIdentifier: [UIView]] = [:]
        var order: [ObjectIdentifier] = []
        var queue: [UIView] = bar.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            let name = String(describing: type(of: view))
            if name.contains("TabButton"), !view.isHidden, view.alpha > 0,
               let parent = view.superview {
                let key = ObjectIdentifier(parent)
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(view)
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        let best = order.max(by: { (groups[$0]?.count ?? 0) < (groups[$1]?.count ?? 0) })
        let buttons = best.flatMap { groups[$0] } ?? []
        return buttons
            .map { Slot(frame: $0.convert($0.bounds, to: bar), title: Self.title(of: $0)) }
            .sorted { $0.frame.midX < $1.frame.midX }
    }

    /// Kept for the callers that only need geometry
    static func tabButtonFrames(in bar: UITabBar) -> [CGRect] {
        tabSlots(in: bar).map(\.frame)
    }

    /// The text drawn inside a bar button
    static func title(of button: UIView) -> String? {
        var queue: [UIView] = button.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let label = view as? UILabel, let text = label.text, !text.isEmpty { return text }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Which section the finger landed on
    static func tab(at point: CGPoint, slots: [Slot]) -> AppTab? {
        guard let index = slotIndex(at: point.x, slots: slots.map(\.frame)) else { return nil }
        if let title = slots[index].title { return tab(named: title) }
        let sections = barSections()
        return index < sections.count ? sections[index] : nil
    }

    /// The section a bar label names
    static func tab(named title: String) -> AppTab? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return AppTab.allCases.first {
            $0.localizedTitle.lowercased() == wanted || $0.titleKey.lowercased() == wanted
        }
    }

    static func slotIndex(at x: CGFloat, slots: [CGRect]) -> Int? {
        guard !slots.isEmpty else { return nil }
        return slots.indices.min(by: { abs(slots[$0].midX - x) < abs(slots[$1].midX - x) })
    }
}

/// The invisible view a menu is anchored to
private final class AnchorButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

extension View {
    /// Hangs the section menu on the tab bar
    func tabBarLongPressMenu() -> some View { modifier(TabBarLongPressMenu()) }
}
#endif
