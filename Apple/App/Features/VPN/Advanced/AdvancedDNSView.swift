import SwiftUI
import VPNProfile

/// Encrypted DNS upstreams, optionally for chosen domains.
struct AdvancedDNSView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var kind = AdvancedDNSUpstream.Kind.doh
    @State private var address = ""
    @State private var domains = ""
    @State private var viaProxy = true

    var body: some View {
        Form {
            Section {
                ForEach(model.profile.dns) { upstream in
                    VStack(alignment: .leading) {
                        Text(verbatim: upstream.address)
                        Text(verbatim: summary(upstream)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in model.update { $0.dns.remove(atOffsets: offsets) } }
            } header: {
                InfoSectionHeader("Upstreams") {
                    Text("DNS over HTTPS, QUIC or TLS, or plain TCP. With domains listed, only those names use the upstream.")
                }
            }
            newSection
        }
        .formStyle(.grouped)
        .screenTitle("DNS")
    }

    private func summary(_ upstream: AdvancedDNSUpstream) -> String {
        let scope = upstream.domains.isEmpty ? "" : " · " + upstream.domains.joined(separator: ", ")
        return upstream.kind.rawValue.uppercased() + scope
    }

    private var newSection: some View {
        Section("New upstream") {
            Picker("Type", selection: $kind) {
                Text("DoH").tag(AdvancedDNSUpstream.Kind.doh)
                Text("DoQ").tag(AdvancedDNSUpstream.Kind.doq)
                Text(verbatim: "DoT").tag(AdvancedDNSUpstream.Kind.dot)
                Text("TCP").tag(AdvancedDNSUpstream.Kind.tcp)
                Text("Plain").tag(AdvancedDNSUpstream.Kind.plain)
            }
            TextField("Address", text: $address)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("Only for domains (comma separated)", text: $domains)
                .autocorrectionDisabled()
            Toggle("Ask through the VPN server", isOn: $viaProxy)
                .disabled(kind == .doq || kind == .plain)
            Button("Add upstream") {
                let list = domains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                model.update { $0.dns.append(AdvancedDNSUpstream(kind: kind, address: address, domains: list, viaProxy: viaProxy)) }
                address = ""
                domains = ""
            }
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
