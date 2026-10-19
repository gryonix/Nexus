import SwiftUI

struct AboutView: View {
    var body: some View {
        CardList {
            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppRelease.version)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(verbatim: AppRelease.build)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Website") {
                    Text(verbatim: "gryonix.com")
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Link(destination: AppRelease.supportChat) {
                    Label {
                        Text(verbatim: "Discord")
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                }
            } header: {
                HStack {
                    Text(verbatim: "gryonixNexus")
                    Spacer()
                    InfoNote("gryonixNexus", "Generates and manages self-hosted services over SSH. There is no backend of ours between this app and your machines.")
                }
            }

            Section {
                Link(destination: AppRelease.sourceRepository) {
                    Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppRelease.securityPolicy) {
                    Label("Security policy", systemImage: "lock.shield")
                }
            } header: {
                InfoSectionHeader("Privacy", note: "No account, no analytics, no server of ours. SSH keys and passwords stay in this device's Keychain, and the fleet is a file in this app's container.")
            }

            Section {
                ForEach(OpenSourceLicense.shipped) { license in
                    NavigationLink {
                        LicenseTextView(license: license)
                    } label: {
                        LabeledContent(license.name) {
                            Text(verbatim: license.terms)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                InfoSectionHeader("Open source", note: "Everything this build links, with the license it is used under.")
            }
        }
        .bottomBarClearance()
        .navigationTitle("About")
        .raisedNavigationTitle()
    }
}

enum AppRelease {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static let sourceRepository = URL(string: "https://github.com/gryonix/Nexus")!
    static let supportChat = URL(string: "https://discord.gg/RsMMRPgzhK")!
    static let securityPolicy = URL(string: "https://github.com/gryonix/Nexus/blob/main/SECURITY.md")!
}

struct OpenSourceLicense: Identifiable, Hashable {
    let id: String
    let name: String
    let terms: String
    let source: Source
    let isMacOnly: Bool

    enum Source: Hashable {
        case package
        /// The tag or version the build recipe pins
        case runtime(pin: String)
        /// One file written by Tools/third-party-notices.py
        case generated
    }

    init(id: String, name: String, terms: String, isMacOnly: Bool = false,
         source: Source = .package) {
        self.id = id
        self.name = name
        self.terms = terms
        self.isMacOnly = isMacOnly
        self.source = source
    }

    var resource: String { id }

    static let notLinked: Set<String> = ["swift-argument-parser"]

    /// Every package any build of this app links
    static let all: [OpenSourceLicense] = [
        .init(id: "BigInt", name: "BigInt", terms: "MIT"),
        .init(id: "Citadel", name: "Citadel", terms: "MIT"),
        .init(id: "Sparkle", name: "Sparkle", terms: "MIT", isMacOnly: true),
        .init(id: "SwiftTerm", name: "SwiftTerm", terms: "MIT"),
        .init(id: "swift-asn1", name: "swift-asn1", terms: "Apache-2.0"),
        .init(id: "swift-atomics", name: "swift-atomics", terms: "Apache-2.0"),
        .init(id: "swift-collections", name: "swift-collections", terms: "Apache-2.0"),
        .init(id: "swift-crypto", name: "swift-crypto", terms: "Apache-2.0"),
        .init(id: "swift-log", name: "swift-log", terms: "Apache-2.0"),
        .init(id: "swift-nio", name: "swift-nio", terms: "Apache-2.0"),
        .init(id: "swift-nio-ssh", name: "swift-nio-ssh", terms: "Apache-2.0"),
        .init(id: "swift-protobuf", name: "swift-protobuf", terms: "Apache-2.0"),
        .init(id: "swift-system", name: "swift-system", terms: "Apache-2.0"),
        .init(id: "WireGuardKit", name: "WireGuardKit (AmneziaWG fork)", terms: "MIT",
              source: .runtime(pin: "v3.1.20260814")),
        .init(id: "LibXray", name: "LibXray", terms: "MIT",
              source: .runtime(pin: "v1.0.2")),
        .init(id: "xray-core", name: "Xray-core (Amnezia fork)", terms: "MPL-2.0",
              source: .runtime(pin: "v1.260724.0")),
        .init(id: "hev-socks5-tunnel", name: "hev-socks5-tunnel", terms: "MIT",
              source: .runtime(pin: "2.9.3")),
        .init(id: "go-modules", name: "Go modules (VPN core)", terms: "Various",
              source: .generated),
    ]

    static var shipped: [OpenSourceLicense] {
        #if os(macOS)
        all
        #else
        all.filter { !$0.isMacOnly }
        #endif
    }

    /// The license text as shipped in the bundle
    func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct LicenseTextView: View {
    let license: OpenSourceLicense

    var body: some View {
        ScrollView {
            Text(verbatim: license.text() ?? String(localized: "This license text is missing from the build."))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .bottomBarClearance()
        .navigationTitle(Text(verbatim: license.name))
        .raisedNavigationTitle()
    }
}
