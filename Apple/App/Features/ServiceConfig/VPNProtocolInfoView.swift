import ServiceCatalog
import SwiftUI

struct VPNProtocolInfo: Identifiable {
    let serviceID: ServiceID
    let summary: LocalizedStringKey
    let speed: Int
    let stealth: Int
    let simplicity: Int

    var id: String { serviceID.rawValue }

    /// Whether this protocol carries traffic to the admin panels
    var reachesAdminPanels: Bool { serviceID == .wireguardVPN }

    static let all: [VPNProtocolInfo] = [
        VPNProtocolInfo(
            serviceID: .wireguardVPN,
            summary: "Modern and extremely fast, with native apps on every platform and minimal battery drain — the de-facto standard for a personal VPN. Its packets are easy for DPI to recognise, so it fits best where VPNs are not actively blocked.",
            speed: 3, stealth: 1, simplicity: 3
        ),
        VPNProtocolInfo(
            serviceID: .amneziaWG,
            summary: "WireGuard with traffic obfuscation: the same speed and simplicity, but the handshake and packets are disguised so deep packet inspection cannot recognise a VPN. A good default where plain WireGuard is blocked — for internet access, not for reaching the admin panels.",
            speed: 3, stealth: 2, simplicity: 3
        ),
        VPNProtocolInfo(
            serviceID: .shadowsocks,
            summary: "A lightweight encrypted proxy that looks like ordinary internet traffic. Very fast, simple clients (Outline), gets through basic blocking well. It is a proxy rather than a full VPN — apps connect through it explicitly.",
            speed: 3, stealth: 2, simplicity: 2
        ),
        VPNProtocolInfo(
            serviceID: .xrayReality,
            summary: "The strongest option against censorship: it borrows a real TLS handshake from a well-known site, so the connection is practically indistinguishable from a normal HTTPS visit. Clients (v2rayN, Hiddify) are a bit more technical.",
            speed: 2, stealth: 3, simplicity: 1
        ),
        VPNProtocolInfo(
            serviceID: .openVPN,
            summary: "The classic, battle-tested VPN: supported by countless routers, firmwares and corporate systems. Slower than WireGuard and easily recognised by DPI, but unmatched in compatibility.",
            speed: 1, stealth: 1, simplicity: 2
        )
    ]

    static func info(for id: ServiceID) -> VPNProtocolInfo? {
        all.first { $0.serviceID == id }
    }
}

struct VPNProtocolInfoView: View {
    let info: VPNProtocolInfo
    @Environment(\.dismiss) private var dismiss

    private var displayName: String {
        ServiceRegistry.service(info.serviceID)?.displayName ?? info.serviceID.rawValue
    }

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    Text(info.summary)
                        .font(.callout)
                } header: {
                    Text("Advantages")
                }

                Section {
                    Label {
                        Text(info.reachesAdminPanels
                             ? "Admin panels (mail, cloud, photos, vault) open over this protocol."
                             : "Admin panels (mail, cloud, photos, vault) do NOT open over this protocol — only over plain WireGuard. Use it for internet access and keep a WireGuard client for management.")
                    } icon: {
                        Image(systemName: info.reachesAdminPanels ? "checkmark.shield" : "lock.slash")
                            .foregroundStyle(info.reachesAdminPanels ? .green : .orange)
                    }
                    .font(.callout)
                } header: {
                    Text("Admin panels")
                }

                Section {
                    comparisonGrid
                } header: {
                    Text("Comparison")
                }
            }
            .navigationTitle(displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private var comparisonGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Protocol")
                Text("Speed")
                Text("Stealth")
                Text("Ease of use")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(VPNProtocolInfo.all) { row in
                GridRow {
                    Text(verbatim: ServiceRegistry.service(row.serviceID)?.displayName
                         ?? row.serviceID.rawValue)
                        .font(.callout.weight(row.id == info.id ? .semibold : .regular))
                        .lineLimit(1)
                    dots(row.speed)
                    dots(row.stealth)
                    dots(row.simplicity)
                }
                .foregroundStyle(row.id == info.id ? AnyShapeStyle(.primary)
                                                   : AnyShapeStyle(.secondary))
            }
        }
    }

    /// "●●○" rating, language-independent by design
    private func dots(_ value: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < value ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

#Preview {
    VPNProtocolInfoView(info: VPNProtocolInfo.all[3])
}
