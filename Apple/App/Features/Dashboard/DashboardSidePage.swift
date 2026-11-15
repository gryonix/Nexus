import ServiceCatalog
import SwiftUI

/// A server page that can open in the right column
enum DashboardSidePage: Hashable {
    case agent, system, configuration, logins, dynamicDNS, notifications
    case security(SecurityRoute)
    case logs(ServiceID)
    case history(MetricsHistoryTarget)
}

extension SecurityRoute {
    var title: LocalizedStringKey {
        switch self {
        case .adminPanels: return "Restrict admin panels"
        case .crowdSec: return "CrowdSec"
        case .sshAccess: return "SSH access"
        }
    }
}

/// The page shown in the right column
struct SidePaneEntry: Identifiable {
    let id: AnyHashable
    let content: AnyView
}

/// Holds the right column's page on a wide phone
@MainActor
final class SidePaneModel: ObservableObject {
    @Published private(set) var entry: SidePaneEntry?

    /// A new page replaces the shown one
    func open(_ id: AnyHashable, @ViewBuilder _ content: () -> some View) {
        entry = SidePaneEntry(id: id, content: AnyView(content()))
    }

    func close() {
        entry = nil
    }
}

/// The server's stack beside an open page
struct SidePaneSplit<Main: View, Pane: View>: View {
    @ObservedObject var model: SidePaneModel
    let wide: Bool
    @ViewBuilder let main: () -> Main
    @ViewBuilder let pane: (SidePaneEntry) -> Pane

    /// The share of the width a page takes
    static var pageShare: CGFloat { 0.55 }

    @State private var width: CGFloat = 0

    private var paneShown: Bool { wide && model.entry != nil }

    var body: some View {
        HStack(spacing: 0) {
            main()
                .frame(maxWidth: .infinity)
                .environment(\.sidePane, wide ? model : nil)
                .environment(\.sidePaneShown, paneShown)
            if paneShown, let entry = model.entry {
                HStack(spacing: 0) {
                    Divider()
                    pane(entry)
                        .environment(\.sidePaneClose, { model.close() })
                }
                .frame(width: width * Self.pageShare)
                .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.smooth, value: model.entry?.id)
        .onChange(of: wide) { _, isWide in
            if !isWide { model.close() }
        }
    }
}

/// Wraps a sheet page in its own stack
struct SheetStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.sidePaneClose) private var paneClose

    var body: some View {
        if paneClose != nil {
            content()
        } else {
            NavigationStack { content() }
        }
    }
}

extension View {
    func subpage(isPresented: Binding<Bool>, @ViewBuilder _ page: @escaping () -> some View) -> some View {
        modifier(Subpage(isPresented: isPresented, page: page))
    }

    /// A close button where a sheet's Done sits
    func withPageClose(_ closeSheet: @escaping () -> Void = {}) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) { PageCloseButton(closeSheet: closeSheet) }
        }
    }
}

/// Rebuilds a column page whenever the server's model changes
struct LivePage<Content: View>: View {
    @ObservedObject var model: DashboardViewModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

/// Pushes inside the column; a sheet elsewhere
private struct Subpage<Page: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let page: () -> Page

    @Environment(\.sidePaneClose) private var paneClose

    func body(content: Content) -> some View {
        if paneClose != nil {
            content.navigationDestination(isPresented: $isPresented, destination: page)
        } else {
            content.sheet(isPresented: $isPresented, content: page)
        }
    }
}

/// Opens a page in the column or pushes it
struct ServerPageLink<Value: Hashable, Label: View>: View {
    let value: Value
    let label: Label

    @Environment(\.sidePane) private var pane

    init(value: Value, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        if let pane {
            Button {
                pane.open(value) { ServerPageDestination(value: value).withPageClose() }
            } label: {
                HStack {
                    label
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: value) { label }
        }
    }
}

/// The screen a pushed server value shows
struct ServerPageDestination: View {
    let value: AnyHashable

    var body: some View {
        switch value.base {
        case let target as MetricsHistoryTarget:
            MetricsHistoryView(deployment: target.deployment, host: target.host,
                               initialMetric: target.metric)
        case let target as EnergyTarget: EnergyView(target: target)
        case let target as StorageTarget: StorageView(target: target)
        case let target as CacheDiskTarget: CacheDiskView(target: target)
        case let target as SpeedTestTarget: SpeedTestView(target: target)
        case let target as TopProcessesTarget: TopProcessesView(target: target)
        default: EmptyView()
        }
    }
}

/// Closes the column page or the sheet
struct PageCloseButton: View {
    var title: LocalizedStringKey = "Done"
    let closeSheet: () -> Void

    @Environment(\.sidePaneClose) private var paneClose

    var body: some View {
        Button(title) { (paneClose ?? closeSheet)() }
    }
}

private struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SidePaneKey: EnvironmentKey {
    static let defaultValue: SidePaneModel? = nil
}

private struct SidePaneShownKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SidePaneCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// The shell has room for a page beside the server
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }

    /// The column server pages open in
    var sidePane: SidePaneModel? {
        get { self[SidePaneKey.self] }
        set { self[SidePaneKey.self] = newValue }
    }

    /// A page sits to the right of the server
    var sidePaneShown: Bool {
        get { self[SidePaneShownKey.self] }
        set { self[SidePaneShownKey.self] = newValue }
    }

    /// Set inside the column: closes its page
    var sidePaneClose: (() -> Void)? {
        get { self[SidePaneCloseKey.self] }
        set { self[SidePaneCloseKey.self] = newValue }
    }
}
