#if os(iOS)
import SwiftUI
import VPNTunnel

/// What the VPN island shows, with a live preview
struct VPNIslandSettingsView: View {
    @ObservedObject private var settings = LiveActivitySettings.shared

    var body: some View {
        Form {
            Section {
                DynamicIslandPreview(model: sampleModel)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            } header: {
                Text("Preview")
            }
            Section("Colour") {
                IslandTintPicker(selection: $settings.vpnIslandStyle.tint)
            }
            Section {
                Picker("Right side", selection: $settings.vpnIslandStyle.compactDetail) {
                    ForEach(VPNIslandStyle.CompactDetail.allCases, id: \.self) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
            } header: {
                Text("Small island")
            }
            Section {
                Toggle("Connection time", isOn: $settings.vpnIslandStyle.showsTimer)
                Toggle("Server", isOn: $settings.vpnIslandStyle.showsServer)
                Toggle("Protocol", isOn: $settings.vpnIslandStyle.showsProtocol)
                Toggle("Traffic", isOn: $settings.vpnIslandStyle.showsTraffic)
            } header: {
                Text("Expanded island")
            } footer: {
                Text("Touch and hold the island to expand it. The round button on the right disconnects after a second tap.")
            }
            Section {
                ForEach(VPNProtocolShortName.renamable, id: \.short) { item in
                    ProtocolLabelField(name: item.name, short: item.short,
                                       labels: $settings.vpnIslandStyle.protocolLabels)
                }
            } header: {
                Text("Protocol names")
            } footer: {
                Text("Your own name for each protocol on the island and the Lock Screen, up to eight characters. Empty keeps the standard one.")
            }
            Section {
                Button("Reset to defaults") { settings.vpnIslandStyle = settings.vpnIslandStyle.islandReset }
            }
        }
        .navigationTitle("Dynamic Island")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sampleModel: VPNIslandModel {
        VPNIslandModel(status: .connected(since: Date().addingTimeInterval(-754)),
                       statistics: TunnelStatistics(received: 48_300_000, sent: 3_100_000, lastHandshake: nil),
                       startedAt: Date().addingTimeInterval(-754),
                       serverName: "example.org",
                       protocolName: "WireGuard",
                       profileName: "iPhone",
                       isSimulated: false,
                       style: settings.vpnIslandStyle,
                       stopArmed: false)
    }
}

/// One protocol's own name, saved when typing ends
private struct ProtocolLabelField: View {
    let name: String
    let short: String
    @Binding var labels: [String: String]?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: Text(verbatim: short)) { Text(verbatim: name) }
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityIdentifier("island.label.\(short)")
                .onSubmit(save)
                .onChange(of: text) { _, new in
                    if new.count > VPNIslandStyle.labelLength { text = String(new.prefix(VPNIslandStyle.labelLength)) }
                }
                .onChange(of: focused) { _, now in if !now { save() } }
        } label: {
            Text(verbatim: name)
        }
        .onAppear { text = labels?[short] ?? "" }
        .onChange(of: labels) { _, new in if !focused { text = new?[short] ?? "" } }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = labels ?? [:]
        updated[short] = trimmed.isEmpty ? nil : trimmed
        let result = updated.isEmpty ? nil : updated
        if result != labels { labels = result }
    }
}

/// The island's colours as tappable dots
private struct IslandTintPicker: View {
    @Binding var selection: VPNIslandStyle.Tint

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
            ForEach(VPNIslandStyle.Tint.allCases, id: \.self) { tint in
                Button {
                    selection = tint
                } label: {
                    VStack(spacing: 4) {
                        swatch(tint)
                        Text(tint.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tint ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ tint: VPNIslandStyle.Tint) -> some View {
        ZStack {
            Circle()
                .fill(tint.color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(
                    AngularGradient(colors: [.green, .orange, .red, .green], center: .center)))
                .frame(width: 30, height: 30)
            if selection == tint {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .frame(width: 38, height: 38)
            }
        }
        .frame(width: 40, height: 40)
    }
}

/// The compact and expanded island drawn with the real views
struct DynamicIslandPreview: View {
    let model: VPNIslandModel

    var body: some View {
        VStack(spacing: 18) {
            compact
            expanded
        }
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
    }

    private var compact: some View {
        HStack(spacing: 0) {
            VPNCompactLeading(model: model)
                .frame(width: 40)
            Spacer(minLength: Self.cameraGap)
            VPNCompactTrailing(model: model)
                .frame(minWidth: 40)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.compactHeight)
        .background(Capsule().fill(Color.black))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Small island"))
    }

    private var expanded: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center) {
                VPNExpandedLeading(model: model)
                Spacer(minLength: 8)
                IslandStopButton(isArmed: false, tint: model.tint) { face in face }
                    .padding(.trailing, IslandLayout.inset)
            }
            VPNExpandedBottom(model: model)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: Self.expandedCorner, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: Self.expandedCorner, style: .continuous)
            .strokeBorder(model.tint.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Expanded island"))
    }

    static let compactHeight: CGFloat = 37
    /// The camera's place between the two sides
    static let cameraGap: CGFloat = 126
    static let expandedCorner: CGFloat = 44
}
#endif
