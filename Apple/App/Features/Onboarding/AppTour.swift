import SwiftUI

/// The first-launch walkthrough: the layout, then a demo server.
@MainActor
final class AppTour: ObservableObject {
    static let shared = AppTour()
    nonisolated static let shownKey = "appTourShown"

    @Published private(set) var step: AppTourStep?
    /// Target frames in global coordinates, published only while touring
    @Published private(set) var frames: [AppTourTarget: CGRect] = [:]
    /// A step whose screen is still moving into place
    @Published private(set) var arriving: AppTourStep?
    /// The one piece of each target a popover hangs from
    @Published private(set) var anchors: [AppTourTarget: UUID] = [:]
    private var parts: [AppTourTarget: [UUID: CGRect]] = [:]

    static var hasBeenShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    func start(at first: AppTourStep? = nil) {
        step = first ?? AppTourStep.tour.first
        publishFrames()
    }

    func startIfDue() {
        guard !Self.hasBeenShown else { return }
        start()
    }

    func next() {
        let steps = AppTourStep.tour
        guard let step, let index = steps.firstIndex(of: step) else { return }
        if index + 1 < steps.count {
            self.step = steps[index + 1]
        } else {
            finish()
        }
    }

    func back() {
        let steps = AppTourStep.tour
        guard let step, let index = steps.firstIndex(of: step), index > 0 else { return }
        self.step = steps[index - 1]
    }

    func finish() {
        step = nil
        arriving = nil
        UserDefaults.standard.set(true, forKey: Self.shownKey)
    }

    /// Holds the spotlight back while the screen moves
    func hold(_ step: AppTourStep) {
        arriving = step
    }

    func arrive(_ step: AppTourStep) {
        if arriving == step { arriving = nil }
    }

    /// One view's piece of a target; nil when it leaves
    func report(_ target: AppTourTarget, part: UUID, frame: CGRect?) {
        parts[target, default: [:]][part] = frame
        if step != nil { publishFrames() }
        publishAnchor(of: target)
    }

    /// The topmost piece, so one popover shows
    private func publishAnchor(of target: AppTourTarget) {
        let top = parts[target]?.min {
            ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX)
        }?.key
        if anchors[target] != top { anchors[target] = top }
    }

    private func publishFrames() {
        frames = parts.compactMapValues { pieces in
            pieces.values.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
        }
    }
}

/// Things on screen a tour step can point at
enum AppTourTarget: Hashable {
    case sectionBar, serverCard, serverStrip, serverSites, serverApps, serverMetrics, serverSecurity
}

/// Where the app should be while a step is shown
enum AppTourPlace: Equatable {
    case fleet
    case server(DashboardTab)
}

enum AppTourStep: Int, CaseIterable, Identifiable {
    case demo, sectionBar, serverCard, serverStrip, sites, apps, metrics, security, tabBarStyle, stripStyle, finish

    /// A step that offers a bar style
    var isStyleChoice: Bool { self == .tabBarStyle || self == .stripStyle }

    var id: Int { rawValue }

    /// The steps this platform shows, in order
    static var tour: [AppTourStep] {
        #if os(macOS)
        allCases.filter { !$0.isStyleChoice }
        #else
        allCases
        #endif
    }

    var place: AppTourPlace {
        switch self {
        case .demo, .sectionBar, .serverCard, .tabBarStyle, .finish: return .fleet
        case .serverStrip, .sites, .security, .stripStyle: return .server(.general)
        case .apps: return .server(.operations)
        case .metrics: return .server(.hosts)
        }
    }

    var target: AppTourTarget? {
        switch self {
        case .demo, .finish: return nil
        case .sectionBar, .tabBarStyle: return .sectionBar
        case .serverCard: return .serverCard
        case .serverStrip, .stripStyle: return .serverStrip
        case .sites: return .serverSites
        case .apps: return .serverApps
        case .metrics: return .serverMetrics
        case .security: return .serverSecurity
        }
    }

    var symbol: String {
        switch self {
        case .demo: return "sparkles"
        case .sectionBar: return "square.grid.2x2"
        case .serverCard: return "server.rack"
        case .serverStrip: return "rectangle.split.3x1"
        case .sites: return "globe"
        case .apps: return "shippingbox"
        case .metrics: return "chart.xyaxis.line"
        case .security: return "shield.lefthalf.filled"
        case .tabBarStyle: return "paintbrush"
        case .stripStyle: return "arrow.left.and.right"
        case .finish: return "checkmark.seal"
        }
    }

    private static var onMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var title: LocalizedStringKey {
        switch self {
        case .demo: return "These servers are a demo"
        case .sectionBar: return Self.onMac ? "The sidebar" : "The sections bar"
        case .serverCard: return "Your servers"
        case .serverStrip: return "A second bar inside each server"
        case .sites: return "Sites and access"
        case .apps: return "Apps"
        case .metrics: return "Metrics"
        case .security: return "Protection"
        case .tabBarStyle: return "Two looks for the bottom bar"
        case .stripStyle: return "Two looks for the server strip"
        case .finish: return "That's the tour"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .demo:
            return "Invented servers, so every screen works before you own one. Nothing here touches a real machine, and they disappear once you add your own server."
        case .sectionBar:
            return Self.onMac
                ? "Servers, Metrics, VPN, Configurator and Settings. Right-click one to choose which sections show."
                : "Servers, Metrics, VPN, Configurator and Settings. Tap to switch, tap the current one again to go back to its start, hold one for more."
        case .serverCard:
            return Self.onMac
                ? "Each card shows a server's state and live load. Click one to open it — the tour opens this one for you."
                : "Each card shows a server's state and live load. Tap one to open it — the tour opens this one for you."
        case .serverStrip:
            return Self.onMac
                ? "The switch in the toolbar changes this server's pages: General, Apps, Metrics and more."
                : "The strip at the top switches this server's pages: General, Apps, Metrics and more."
        case .sites:
            return "Every app this server runs, with its address. Below: logins and passwords, and the DNS, DKIM and port records to set up."
        case .apps:
            return "Start, stop, update and back up each app, and read its logs. An update rolls back by itself if the new version does not come up."
        case .metrics:
            return "Live CPU, memory, disk and traffic for every machine. Open a chart to see further back."
        case .security:
            return "CrowdSec stops attackers. See who was blocked, block addresses by hand, and set automatic rules — by country too."
        case .tabBarStyle:
            return "This app's own bar or the system's. Try it — the bar below changes right away. Also in Settings → Appearance → Bars."
        case .stripStyle:
            return "Ours scrolls sideways when a server has more sections than fit; the system's squeezes them and cuts the names. Try both — the strip above changes right away."
        case .finish:
            return "When you are ready, add your own server in Configurator. The tour is always in Settings."
        }
    }
}

private struct AppTourTargetReporter: ViewModifier {
    let target: AppTourTarget
    @State private var part = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                AppTour.shared.report(target, part: part, frame: frame)
            }
            .onDisappear { AppTour.shared.report(target, part: part, frame: nil) }
            #if os(macOS)
            .modifier(AppTourPopover(target: target, part: part))
            #endif
    }
}

extension View {
    /// Marks this view as something the tour can spotlight
    func appTourTarget(_ target: AppTourTarget) -> some View {
        modifier(AppTourTargetReporter(target: target))
    }
}
