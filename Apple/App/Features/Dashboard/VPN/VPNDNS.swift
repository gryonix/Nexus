import AgentControl
import Network
import ServiceCatalog
import SwiftUI

/// What a public resolver refuses to answer
enum DNSBlocking: Hashable {
    case nothing, malware, ads, adult, adsAndAdult

    var label: LocalizedStringKey {
        switch self {
        case .nothing: "Nothing"
        case .malware: "Malware"
        case .ads: "Ads and trackers"
        case .adult: "Malware and adult sites"
        case .adsAndAdult: "Ads and adult sites"
        }
    }
}

/// One public resolver a VPN device can use
struct PublicDNS: Identifiable, Hashable {
    let id: String
    let provider: String
    /// Nil for the provider's plain resolver
    let variant: String?
    let addresses: [String]
    let blocks: DNSBlocking
    let speed: Int
    let privacy: Int
    let summary: String

    var name: String {
        guard let variant else { return provider }
        return UIL10n.string("%@ — %@", provider, UIL10n.string(variant))
    }

    static let all: [PublicDNS] = [
        PublicDNS(id: "cloudflare", provider: "Cloudflare", variant: nil,
                  addresses: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"],
                  blocks: .nothing, speed: 3, privacy: 3, summary: cloudflare),
        PublicDNS(id: "cloudflare-malware", provider: "Cloudflare", variant: "malware blocking",
                  addresses: ["1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"],
                  blocks: .malware, speed: 3, privacy: 3, summary: cloudflare),
        PublicDNS(id: "cloudflare-family", provider: "Cloudflare", variant: "family",
                  addresses: ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"],
                  blocks: .adult, speed: 3, privacy: 3, summary: cloudflare),
        PublicDNS(id: "google", provider: "Google", variant: nil,
                  addresses: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"],
                  blocks: .nothing, speed: 3, privacy: 1,
                  summary: "Fast everywhere and very reliable. Google keeps logs of queries for a while, so it is the weakest choice for privacy."),
        PublicDNS(id: "quad9", provider: "Quad9", variant: nil,
                  addresses: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"],
                  blocks: .malware, speed: 2, privacy: 3,
                  summary: "A non-profit in Switzerland that blocks known malware and phishing domains and keeps no personal data."),
        PublicDNS(id: "adguard", provider: "AdGuard DNS", variant: nil,
                  addresses: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"],
                  blocks: .ads, speed: 2, privacy: 2, summary: adguard),
        PublicDNS(id: "adguard-family", provider: "AdGuard DNS", variant: "family",
                  addresses: ["94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"],
                  blocks: .adsAndAdult, speed: 2, privacy: 2, summary: adguard),
        PublicDNS(id: "dns4eu", provider: "DNS4EU", variant: nil,
                  addresses: ["86.54.11.1", "86.54.11.201", "2a13:1001::86:54:11:1", "2a13:1001::86:54:11:201"],
                  blocks: .malware, speed: 2, privacy: 3, summary: dns4eu),
        PublicDNS(id: "dns4eu-ads", provider: "DNS4EU", variant: "no ads",
                  addresses: ["86.54.11.13", "86.54.11.213", "2a13:1001::86:54:11:13", "2a13:1001::86:54:11:213"],
                  blocks: .ads, speed: 2, privacy: 3, summary: dns4eu),
        PublicDNS(id: "dns4eu-child", provider: "DNS4EU", variant: "child protection",
                  addresses: ["86.54.11.12", "86.54.11.212", "2a13:1001::86:54:11:12", "2a13:1001::86:54:11:212"],
                  blocks: .adult, speed: 2, privacy: 3, summary: dns4eu),
        PublicDNS(id: "opendns", provider: "OpenDNS", variant: nil,
                  addresses: ["208.67.222.222", "208.67.220.220", "2620:119:35::35", "2620:119:53::53"],
                  blocks: .nothing, speed: 2, privacy: 1, summary: opendns),
        PublicDNS(id: "opendns-family", provider: "OpenDNS", variant: "FamilyShield",
                  addresses: ["208.67.222.123", "208.67.220.123", "2620:119:35::123", "2620:119:53::123"],
                  blocks: .adult, speed: 2, privacy: 1, summary: opendns),
    ]

    private static let cloudflare = "The fastest public resolver in most places. Cloudflare deletes query logs within a day and is audited for it."
    private static let adguard = "Blocks ads and trackers for every app on the device, without installing anything. Run from Cyprus."
    private static let dns4eu = "The European Union's own resolver, run under EU privacy law. Blocks malware; other modes also block ads or adult sites."
    private static let opendns = "Cisco's resolver, one of the oldest. Reliable, but owned by a US company that keeps query data."

    /// The preset these addresses belong to, in any order
    static func matching(_ addresses: [String]) -> PublicDNS? {
        let wanted = Set(addresses.map { $0.lowercased() })
        return all.first { Set($0.addresses.map { $0.lowercased() }) == wanted }
    }

    /// A device's DNS, marked as a public service
    static func label(for addresses: [String]) -> String {
        if addresses.isEmpty { return UIL10n.string("%@ (public)", "Cloudflare") }
        guard let preset = matching(addresses) else { return addresses.joined(separator: ", ") }
        return UIL10n.string("%@ (public)", preset.name)
    }

    /// One to four valid addresses, else nil
    static func parse(_ text: String) -> [String]? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == ";" })
            .map(String.init)
        guard (1...4).contains(parts.count) else { return nil }
        for part in parts where IPv4Address(part) == nil && IPv6Address(part) == nil { return nil }
        return parts
    }
}

/// AdGuard Home or Pi-hole on the VPN's own server
struct LocalDNS: Hashable {
    /// Empty when the server cannot relay one
    var address = ""
    /// The resolvers devices can reach there
    var services: [ServiceID] = []

    init(address: String = "", services: [ServiceID] = []) {
        self.address = address
        self.services = services
    }

    init(_ defaults: VPNDNSDefaults) {
        self.init(address: defaults.localAddress, services: defaults.localServices)
    }

    /// Where the agent relays its server's resolver
    static let serverAddress = "10.53.0.53"

    var isOffered: Bool { !address.isEmpty && !services.isEmpty }

    /// The choice itself, without the trailing relay
    static func chosen(_ dns: [String]) -> [String] {
        guard dns.count > 1, dns.last == serverAddress else { return dns }
        return Array(dns.dropLast())
    }

    func isChosen(_ addresses: [String]) -> Bool {
        !address.isEmpty && addresses == [address]
    }

    /// Chosen, but no resolver answers there
    func isGone(_ addresses: [String]) -> Bool {
        isChosen(addresses) && services.isEmpty
    }

    /// The resolvers' names, marked as the user's server
    var name: String {
        let names = services.map { ServiceRegistry.service($0)?.displayName ?? $0.rawValue }
        guard !names.isEmpty else { return UIL10n.string("This server's DNS") }
        return UIL10n.string("%@ (your server)", names.joined(separator: " / "))
    }

    /// What a device's DNS is called in the app
    func name(for addresses: [String]) -> String {
        if isChosen(addresses) { return name }
        if addresses == [Self.serverAddress] { return UIL10n.string("This server's DNS") }
        return PublicDNS.label(for: addresses)
    }
}

/// The last resolver each server offered, kept across launches
enum LocalDNSMemory {
    static func key(_ serverID: UUID) -> String { "vpn.localDNS.\(serverID.uuidString)" }

    static func recall(_ serverID: UUID, in defaults: UserDefaults = .standard) -> LocalDNS? {
        guard let saved = defaults.stringArray(forKey: key(serverID)), let address = saved.first else { return nil }
        return LocalDNS(address: address, services: saved.dropFirst().map { ServiceID(rawValue: $0) })
    }

    static func keep(_ local: LocalDNS, for serverID: UUID, in defaults: UserDefaults = .standard) {
        guard local.isOffered else { return }
        defaults.set([local.address] + local.services.map(\.rawValue), forKey: key(serverID))
    }
}

/// The DNS row: server resolver, public ones, typed addresses
struct VPNDNSMenu: View, Equatable {
    let title: LocalizedStringKey
    let addresses: [String]
    var local = LocalDNS()
    /// Whose DNS this row changes
    var owner: UUID?
    let onChoose: ([String]) -> Void
    @State private var typing = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.addresses == rhs.addresses && lhs.local == rhs.local && lhs.owner == rhs.owner
    }

    private var shown: [String] { LocalDNS.chosen(addresses) }

    var body: some View {
        MenuRow(title, value: local.name(for: shown),
                valueStyle: local.isGone(shown) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)) {
            if local.isOffered {
                Section("On your server") {
                    choice(local.name, chosen: local.isChosen(shown)) { onChoose([local.address]) }
                }
            }
            Section("Public DNS") {
                ForEach(PublicDNS.all) { preset in
                    choice(preset.name, chosen: PublicDNS.matching(shown)?.id == preset.id) {
                        onChoose(preset.addresses)
                    }
                }
            }
            Section {
                Button("Other addresses…") { typing = true }
            }
        }
        .sheet(isPresented: $typing) {
            OwnDNSSheet(current: typedCurrent) { chosen in
                typing = false
                if let chosen { onChoose(chosen) }
            }
        }
    }

    private var typedCurrent: [String] {
        PublicDNS.matching(addresses) == nil && !local.isChosen(addresses) ? addresses : []
    }

    private func choice(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        VerbatimMenuChoice(name, picked: chosen, choose: action)
    }
}

/// One or several addresses typed by hand
struct OwnDNSSheet: View {
    let current: [String]
    let onDone: ([String]?) -> Void
    @State private var text = ""

    private var parsed: [String]? { PublicDNS.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $text, prompt: Text(verbatim: "1.1.1.1, 2606:4700:4700::1111")) {
                        Text("DNS servers")
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                } header: {
                    Text("DNS servers")
                } footer: {
                    Text("One to four IPv4 or IPv6 addresses, separated by commas.")
                        .foregroundStyle(!text.isEmpty && parsed == nil ? .red : .secondary)
                }
            }
            .onAppear { if text.isEmpty { text = current.joined(separator: ", ") } }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 220)
            #endif
            .navigationTitle("Your own DNS")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(parsed) }
                        .disabled(parsed == nil)
                }
            }
        }
    }
}

/// Public resolvers side by side
struct PublicDNSInfoView: View {
    var highlighted: PublicDNS?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CardList {
                if let highlighted {
                    Section {
                        Text(UIL10n.string(highlighted.summary))
                            .font(.callout)
                        Text(verbatim: highlighted.addresses.joined(separator: "\n"))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text(verbatim: highlighted.name)
                    }
                }
                Section {
                    comparisonGrid
                } header: {
                    Text("Comparison")
                } footer: {
                    Text("Every device can use its own DNS. A choice here changes only devices added after it.")
                }
            }
            .navigationTitle("Public DNS")
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
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private var comparisonGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Service")
                Text("Speed")
                Text("Privacy")
                Text("Blocks")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(PublicDNS.all) { row in
                let current = row.id == highlighted?.id
                GridRow {
                    Text(verbatim: row.name)
                        .font(.callout.weight(current ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    RatingDots(value: row.speed)
                    RatingDots(value: row.privacy)
                    Text(row.blocks.label)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
    }
}

/// "●●○", language-independent by design
struct RatingDots: View {
    let value: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < value ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// What the chosen DNS reaches, per protocol
struct VPNDNSFootnote: View {
    let protocolID: ServiceID
    var changing = false
    /// The chosen resolver left this server
    var resolverGone = false

    var body: some View {
        if resolverGone {
            Text("AdGuard Home or Pi-hole is no longer on this server. Until you choose another DNS, answers come from Cloudflare.")
                .foregroundStyle(.orange)
        } else if protocolID == .shadowsocks || protocolID == .xrayReality {
            Text("This app uses it. In another proxy app, set the DNS in that app.")
        } else if changing {
            Text("A device that imported the file by hand needs it again after a change.")
        } else {
            Text("Written into this device's configuration.")
        }
    }
}
