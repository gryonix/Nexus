import ServerControl
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// "Settings" tab root
struct AppSettingsView: View {
    @State private var path = NavigationPath()
    @ObservedObject private var navigator = AppNavigator.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $path) {
            navigation(form)
        }
        .popToRootOnReselect(.settings) { path = NavigationPath() }
    }

    private var form: some View {
        Form {
            LicenseSettingsSection()
            generalSection
            networkSection
            platformSections
            aboutSections
        }
    }

    private var generalSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }
            NavigationLink {
                TabBarSettingsView()
            } label: {
                Label("Sections", systemImage: "square.grid.2x2")
            }
            NavigationLink {
                SecuritySettingsView()
            } label: {
                Label("Security", systemImage: "lock.shield")
            }
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Push notifications", systemImage: "bell.badge")
            }
            #if os(iOS)
            NavigationLink {
                LiveActivitySettingsView()
            } label: {
                Label("Live Activity & Dynamic Island", systemImage: "platter.filled.top.iphone")
            }
            #endif
        }
    }

    private var networkSection: some View {
        Section {
            NavigationLink {
                DNSAPISettingsView().licenseLocked()
            } label: {
                Label("DNS API", systemImage: "cloud")
            }
            NavigationLink {
                ProxySettingsView().licenseLocked()
            } label: {
                Label("Proxies", systemImage: "arrow.triangle.swap")
            }
        }
    }

    @ViewBuilder
    private var platformSections: some View {
        #if os(macOS)
        MenuBarSettingsSection()
        #endif

        #if os(macOS)
        AppUpdateSection()
        #endif

        #if DEBUG
        Section {
            NavigationLink(value: SettingsPage.widgetGallery) {
                Label("Widget gallery", systemImage: "square.grid.2x2")
            }
        } footer: {
            Text(verbatim: "Debug builds only.")
        }
        #endif

        #if os(iOS)
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("App System Settings", systemImage: "gear")
            }
            .rowActionButtonStyle()
        } footer: {
            Text("Language, notifications, Face ID and local network access for this app — the settings the phone owns rather than the app.")
        }
        #endif
    }

    @ViewBuilder
    private var aboutSections: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About", systemImage: "info.circle")
            }
            Button {
                navigator.requestedTab = .servers
                AppTour.shared.start()
            } label: {
                Label("Take the tour", systemImage: "hand.point.up.left")
            }
            Link(destination: AppRelease.website) {
                Label("Website", systemImage: "globe")
            }
            Link(destination: AppRelease.sourceRepository) {
                Label {
                    Text(verbatim: "GitHub")
                } icon: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }

    private func navigation(_ base: some View) -> some View {
        base
            #if os(macOS)
            .formStyle(.grouped)
            .formRowButtons()
            .frame(minWidth: 420, minHeight: 300)
            #endif
            .bottomBarClearance()
            .navigationTitle("Settings")
            .sectionToolbar(.settings)
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .appearance: AppearanceSettingsView()
                case .proxies: ProxySettingsView().licenseLocked()
                case .sections: TabBarSettingsView()
                #if DEBUG
                case .widgetGallery: WidgetGalleryView()
                #endif
                }
            }
            .onReceive(navigator.$settingsPage.compactMap { $0 }) { page in
                open(page)
            }
            .task {
                if let page = navigator.settingsPage { open(page) }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_APPEARANCE"] != nil {
                    path.append(SettingsPage.appearance)
                }
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_PROXIES"] != nil {
                    path.append(SettingsPage.proxies)
                }
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_WIDGETS"] != nil {
                    path.append(SettingsPage.widgetGallery)
                }
            }
            #endif
    }

    private func open(_ page: SettingsPage) {
        navigator.settingsPage = nil
        path.append(page)
    }

    enum SettingsPage: Hashable {
        case appearance
        case proxies
        case sections
        #if DEBUG
        /// Every widget, drawn from this device's own snapshot
        case widgetGallery
        #endif
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppAccentSettings.choiceKey)
    private var accentRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(MetricsDisplaySettings.cardColumnsKey)
    private var cardColumnsRaw = ServerCardColumns.one.rawValue
    @ObservedObject private var tabs = TabBarSettings.shared
    @ObservedObject private var metrics = MetricsPreferences.shared

    private var accent: AppAccentChoice { AppAccentChoice(rawValue: accentRaw) ?? .app }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AppearanceAppView()
                } label: {
                    pageRow("App", systemImage: "app.badge", value: Text(accent.title))
                }
                #if os(iOS)
                NavigationLink {
                    AppearanceBarsView()
                } label: {
                    pageRow("Bars", systemImage: "rectangle.bottomthird.inset.filled",
                            value: Text(tabs.barStyle.title))
                }
                #endif
                NavigationLink {
                    AppearanceCardsView()
                } label: {
                    pageRow("Server cards", systemImage: "rectangle.grid.1x2",
                            value: Text(MetricsDisplaySettings
                                .cardColumns(from: cardColumnsRaw).cardSize.localizedName))
                }
                NavigationLink {
                    AppearanceChartsView()
                } label: {
                    pageRow("Metrics and charts", systemImage: "chart.xyaxis.line",
                            value: Text(verbatim: "\(metrics.offeredRanges.count)/\(HistoryRange.allCases.count) · \(metrics.offeredMetrics.count)/\(HistoryMetric.allCases.count)"))
                }
                NavigationLink {
                    AppearanceServerScreenView()
                } label: {
                    pageRow("Server screen", systemImage: "square.stack.3d.up",
                            value: Text(ServiceGroupingChoice(
                                override: tabs.groupServicesByCategoryOverride).title))
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Appearance")
        .raisedNavigationTitle()
    }

    private func pageRow(_ title: LocalizedStringKey,
                         systemImage: String,
                         value: Text) -> some View {
        LabeledContent {
            value.foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

struct AppearanceAppView: View {
    @AppStorage(Haptics.settingKey) private var hapticsEnabled = true

    var body: some View {
        Form {
            AppIconPicker()

            AppAccentPicker()

            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
            } header: {
                InfoSectionHeader("Haptic feedback") {
                    #if os(macOS)
                    Text("Buttons answer a press with a short tap. Only trackpads that support it can play one.")
                    #else
                    Text("Buttons answer a press with a short tap.")
                    #endif
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("App")
        .raisedNavigationTitle()
    }
}

#if os(iOS)
struct AppearanceBarsView: View {
    @ObservedObject private var tabs = TabBarSettings.shared

    var body: some View {
        Form {
            Section {
                WrappingPicker("Bottom tab bar", selection: $tabs.barStyle) {
                    ForEach(BarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                WrappingPicker("Server section strip", selection: $tabs.sectionStripStyle) {
                    ForEach(BarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                WrappingPicker("Server section labels", selection: $tabs.sectionLabels) {
                    ForEach(SectionLabels.allCases) { labels in
                        Text(labels.title).tag(labels)
                    }
                }
                WrappingPicker("Server groups", selection: $tabs.groupStripStyle) {
                    ForEach(BarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                WrappingPicker("Metrics period", selection: $tabs.periodStripStyle) {
                    ForEach(BarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            } header: {
                InfoSectionHeader("Bars", note: "This app's own bar scrolls and shows every section; Apple's divides the width evenly. The bar at the bottom of the app, the section strip at the top of a server and the strip of server groups are set separately. Holding a group for its own menu — rename, delete, which servers are in it — works on either strip.")
            }
        }
        .bottomBarClearance()
        .navigationTitle("Bars")
        .raisedNavigationTitle()
    }
}
#endif

struct AppearanceCardsView: View {
    @AppStorage(MetricsDisplaySettings.indicatorStyleKey)
    private var indicatorStyleRaw = MetricsIndicatorStyle.bars.rawValue
    @AppStorage(MetricsDisplaySettings.cardColumnsKey)
    private var cardColumnsRaw = ServerCardColumns.one.rawValue
    @AppStorage(WakeButtonSettings.delayKey) private var wakeDelay = WakeButtonSettings.defaultDelay

    var body: some View {
        Form {
            cardsSection
            ConnectionSettingsSection()
            Section {
                WrappingPicker("Show after", selection: $wakeDelay) {
                    ForEach(WakeButtonSettings.delays, id: \.self) { seconds in
                        Text(verbatim: WakeButtonSettings.title(seconds)).tag(seconds)
                    }
                }
            } header: {
                InfoSectionHeader("Wake up", note: "A card offers Wake up once its machine at home has not answered for this long, and only while this device is on that machine's network.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Server cards")
        .raisedNavigationTitle()
    }

    private var cardsSection: some View {
        Section {
            WrappingPicker("Default card size", selection: Binding(
                get: { MetricsDisplaySettings.cardColumns(from: cardColumnsRaw) },
                set: { cardColumnsRaw = $0.rawValue }
            )) {
                ForEach(ServerCardColumns.allCases) { columns in
                    Text(columns.cardSize.localizedName).tag(columns)
                }
            }
            WrappingPicker("Load indicator", selection: $indicatorStyleRaw) {
                Text("Bars").tag(MetricsIndicatorStyle.bars.rawValue)
                Text("Line").tag(MetricsIndicatorStyle.track.rawValue)
                Text("Rings").tag(MetricsIndicatorStyle.rings.rawValue)
                Text("Minimal").tag(MetricsIndicatorStyle.minimal.rawValue)
            }
        } header: {
            InfoSectionHeader("Server metric cards", note: "Half-width cards carry fewer numbers and share a row with each other. This is the starting size for every server; a single card can be resized from its own menu, and the load indicator can be overridden per server too.")
        }
    }
}

struct AppearanceChartsView: View {
    @AppStorage(MetricsDisplaySettings.historyInlineKey)
    private var historyInline = false
    @AppStorage(MetricsDisplaySettings.historyAutoScaleKey)
    private var historyAutoScale = true
    @ObservedObject private var metrics = MetricsPreferences.shared

    var body: some View {
        Form {
            Section {
                WrappingPicker("Metrics history", selection: $historyInline) {
                    Text("Separate screen").tag(false)
                    Text("Inline").tag(true)
                }
                WrappingPicker("Chart scale", selection: $historyAutoScale) {
                    Text("Auto").tag(true)
                    Text(verbatim: "0–100%").tag(false)
                }
            } header: {
                InfoSectionHeader("Charts", note: "Inline unfolds the history chart under the host instead of opening a separate screen. Auto fits the chart scale to the data, so small variations stay visible.")
            }

            Section {
                NavigationLink {
                    OfferedRangesView()
                } label: {
                    LabeledContent("Periods") {
                        Text(verbatim: "\(metrics.offeredRanges.count)/\(HistoryRange.allCases.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    OfferedMetricsView()
                } label: {
                    LabeledContent("Metrics") {
                        Text(verbatim: "\(metrics.offeredMetrics.count)/\(HistoryMetric.allCases.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                InfoSectionHeader("What the charts offer", note: "The periods on the slider under a chart, and the metrics in its menu. Nothing about how they are measured changes — this only decides what you are offered. At least one of each always stays on.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Metrics and charts")
        .raisedNavigationTitle()
    }
}

struct AppearanceServerScreenView: View {
    @ObservedObject private var tabs = TabBarSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Collapsible sites list", isOn: $tabs.sitesCollapsible)
                WrappingPicker("Group services by category", selection: groupingChoice) {
                    ForEach(ServiceGroupingChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            } header: {
                InfoSectionHeader("Server screen", note: "The server screen lists every installed service's web address. With a full catalog that is a dozen links pushing the rest of the screen down — the first switch lets that section be folded away. Grouping files installed services under their category (Files, Media, VPN, …) instead of listing them one by one; on Automatic it turns itself on for a server that runs two or more services of the same kind, which is when a category header actually shortens the list.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Server screen")
        .raisedNavigationTitle()
    }
}

enum ServiceGroupingChoice: String, CaseIterable, Identifiable, Hashable {
    case automatic, always, never

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: return "Automatic"
        case .always: return "Always"
        case .never: return "Never"
        }
    }

    init(override: Bool?) {
        switch override {
        case .none: self = .automatic
        case .some(true): self = .always
        case .some(false): self = .never
        }
    }

    /// What this choice stores
    var override: Bool? {
        switch self {
        case .automatic: return nil
        case .always: return true
        case .never: return false
        }
    }
}

extension AppearanceServerScreenView {
    /// The stored override (`nil` = automatic) as a picker selection
    var groupingChoice: Binding<ServiceGroupingChoice> {
        Binding {
            ServiceGroupingChoice(override: tabs.groupServicesByCategoryOverride)
        } set: { choice in
            tabs.groupServicesByCategoryOverride = choice.override
        }
    }
}

#Preview {
    AppSettingsView()
}

/// When a card says No connection, and when it reconnects
struct ConnectionSettingsSection: View {
    @AppStorage(ConnectionSettings.silenceKey) private var silence = ConnectionSettings.defaultSilence
    @AppStorage(ConnectionSettings.reconnectKey) private var reconnect = ConnectionSettings.defaultReconnect
    @State private var editingSilence = false
    @State private var editingReconnect = false

    var body: some View {
        Section {
            WrappingPicker("No connection after", selection: choice($silence, editing: $editingSilence)) {
                options(ConnectionSettings.silences, current: silence)
            }
            WrappingPicker("Reconnect after", selection: choice($reconnect, editing: $editingReconnect)) {
                options(ConnectionSettings.reconnects, current: reconnect)
            }
        } header: {
            InfoSectionHeader("Connection", note: "A card says No connection once its server has not answered for this long. After the longer wait the app opens a new connection; on a slow mobile network, longer waits are gentler on the server.")
        }
        .customSeconds("No connection after", isPresented: $editingSilence,
                       range: ConnectionSettings.silenceRange) { silence = $0 }
        .customSeconds("Reconnect after", isPresented: $editingReconnect,
                       range: ConnectionSettings.reconnectRange) { reconnect = $0 }
    }

    /// Other time opens the seconds field
    private func choice(_ value: Binding<Int>, editing: Binding<Bool>) -> Binding<Int> {
        Binding(get: { value.wrappedValue },
                set: { picked in
                    if picked == Self.otherTag { editing.wrappedValue = true } else { value.wrappedValue = picked }
                })
    }

    @ViewBuilder
    private func options(_ presets: [Int], current: Int) -> some View {
        ForEach(presets.contains(current) ? presets : presets + [current], id: \.self) { seconds in
            if seconds == 0 {
                Text("Never").tag(seconds)
            } else {
                Text(verbatim: ConnectionSettings.title(seconds)).tag(seconds)
            }
        }
        Text("Other time…").tag(Self.otherTag)
    }

    private static let otherTag = -1
}

/// Asks for a wait in seconds within a range
struct CustomSeconds: ViewModifier {
    let title: LocalizedStringKey
    @Binding var isPresented: Bool
    let range: ClosedRange<Int>
    let onSet: (Int) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField("Seconds", text: $text)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Set") {
                if let seconds = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(seconds) {
                    onSet(seconds)
                }
                text = ""
            }
            Button("Cancel", role: .cancel) { text = "" }
        } message: {
            Text("From \(range.lowerBound) to \(range.upperBound) seconds.")
        }
    }
}

extension View {
    func customSeconds(_ title: LocalizedStringKey, isPresented: Binding<Bool>,
                       range: ClosedRange<Int>, onSet: @escaping (Int) -> Void) -> some View {
        modifier(CustomSeconds(title: title, isPresented: isPresented, range: range, onSet: onSet))
    }
}
