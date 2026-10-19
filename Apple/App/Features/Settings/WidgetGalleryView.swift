#if DEBUG
import SwiftUI
import VPNTunnel
import WidgetKit

/// Every widget this app will ship, drawn inside the app
struct WidgetGalleryView: View {
    @State private var useRealSnapshot = true
    @State private var entry = WidgetSnapshotReader.entry()

    var body: some View {
        ScrollViewReader { scroller in
        CardList {
            Section {
                Toggle(isOn: $useRealSnapshot) { Text(verbatim: "Draw from this device's snapshot") }
                Button {
                    reload()
                } label: {
                    Label { Text(verbatim: "Read the snapshot again") } icon: { Image(systemName: "arrow.clockwise") }
                }
                .rowActionButtonStyle()
            } footer: {
                Text(verbatim: sourceDescription)
            }

            Section {
                gallery(.systemSmall, label: "Small")
                gallery(.systemMedium, label: "Medium")
                gallery(.systemLarge, label: "Large")
            } header: {
                Text(verbatim: "Home screen")
            }
            .id(Anchor.home)

            #if os(iOS)
            Section {
                gallery(.accessoryCircular, label: "Circular")
                gallery(.accessoryRectangular, label: "Rectangular")
                gallery(.accessoryInline, label: "Inline")
            } header: {
                Text(verbatim: "Lock screen")
            } footer: {
                Text(verbatim: "These sizes are drawn without the lock screen's own tint, so judge the layout here and the colour on a device.")
            }
            .id(Anchor.lock)
            #endif

            Section {
                sized(DevicesWidgetView(entry: shown), .systemSmall, label: "Small")
                sized(DevicesWidgetView(entry: shown), .systemMedium, label: "Medium")
            } header: {
                Text(verbatim: "Devices")
            }
            .id(Anchor.devices)
        }
        .navigationTitle(Text(verbatim: "Widget gallery"))
        .raisedNavigationTitle()
        .onAppear(perform: reload)
        .task {
            guard let wanted = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_WIDGET_SECTION"],
                  let anchor = Anchor(rawValue: wanted) else { return }
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation { scroller.scrollTo(anchor, anchor: .top) }
        }
        }
    }

    private enum Anchor: String, Hashable { case home, lock, devices }

    private var shown: TunnelEntry {
        useRealSnapshot ? entry : WidgetSnapshotReader.placeholder
    }

    private var sourceDescription: String {
        guard useRealSnapshot else {
            return UIL10n.string("Drawn from the built-in example fleet.")
        }
        guard let snapshot = entry.snapshot else {
            return UIL10n.string("No snapshot has been written yet — open a server's VPN devices and come back.")
        }
        let age = TunnelPresentation.age(of: snapshot.generatedAt)
        return UIL10n.string("Snapshot from %@ — %lld servers, %lld devices.",
                             age, snapshot.servers.count, snapshot.deviceCount)
    }

    private func reload() {
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SEED_SNAPSHOT"] != nil {
            FleetSnapshotStore().write(.placeholder)
        }
        entry = WidgetSnapshotReader.entry()
    }

    private func gallery(_ family: WidgetFamily, label: String) -> some View {
        sized(VPNStatusWidgetView(entry: shown, familyOverride: family), family, label: label)
    }

    /// One widget at the size WidgetKit would give it
    private func sized(_ content: some View, _ family: WidgetFamily,
                       label: String) -> some View {
        let size = Self.size(family)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
            accessoryStyled(content, family)
                .padding(Self.inset(family))
                .frame(width: size.width, height: size.height,
                       alignment: Self.alignment(family))
                .background(.quaternary, in: Self.shape(family))
                .clipShape(Self.shape(family))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func accessoryStyled(_ content: some View, _ family: WidgetFamily) -> some View {
        if Self.isInline(family) {
            content
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            content
        }
    }

    /// Where the content sits in its slot
    private static func alignment(_ family: WidgetFamily) -> Alignment {
        #if os(iOS)
        if family == .accessoryCircular { return .center }
        if family == .accessoryInline { return .leading }
        #endif
        return .topLeading
    }

    private static func isInline(_ family: WidgetFamily) -> Bool {
        #if os(iOS)
        return family == .accessoryInline
        #else
        return false
        #endif
    }

    /// The padding each family's content actually gets
    private static func inset(_ family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge: return 12
        default:
            #if os(iOS)
            if family == .accessoryInline { return 0 }
            if family == .accessoryCircular { return 4 }
            if family == .accessoryRectangular { return 2 }
            #endif
            return 12
        }
    }

    private static func shape(_ family: WidgetFamily) -> AnyShape {
        #if os(iOS)
        if family == .accessoryCircular { return AnyShape(Circle()) }
        if family == .accessoryInline { return AnyShape(Capsule()) }
        if family == .accessoryRectangular {
            return AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        #endif
        return AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: return CGSize(width: 158, height: 158)
        case .systemMedium: return CGSize(width: 338, height: 158)
        case .systemLarge: return CGSize(width: 338, height: 354)
        default:
            #if os(iOS)
            if family == .accessoryCircular { return CGSize(width: 76, height: 76) }
            if family == .accessoryRectangular { return CGSize(width: 172, height: 76) }
            if family == .accessoryInline { return CGSize(width: 250, height: 26) }
            #endif
            return CGSize(width: 158, height: 158)
        }
    }
}
#endif
