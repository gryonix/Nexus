import SwiftUI
import VPNProfile

/// Domains answered with a chosen address, off by default.
struct AdvancedRewritesView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var domain = ""
    @State private var target = ""

    var body: some View {
        Form {
            Section {
                Toggle("Use host rewrites", isOn: enabledBinding)
            } header: {
                InfoSectionHeader("Host rewrites") {
                    Text("The tunnel answers a domain with your address or another domain. HTTPS sites still have to show a valid certificate. Traffic inspection and scripts are not offered: they need a root certificate trusted on this device.")
                }
            }
            Section {
                ForEach(model.profile.hosts) { rewrite in
                    VStack(alignment: .leading) {
                        Text(verbatim: rewrite.domain)
                        Text(verbatim: "→ \(rewrite.target)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in model.update { $0.hosts.remove(atOffsets: offsets) } }
            }
            newSection
        }
        .formStyle(.grouped)
        .screenTitle("Host rewrites")
    }

    private var newSection: some View {
        Section {
            TextField("Domain", text: $domain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("IP address or domain", text: $target)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Add rewrite") {
                let rewrite = AdvancedHostRewrite(domain: domain.trimmingCharacters(in: .whitespaces),
                                                  target: target.trimmingCharacters(in: .whitespaces))
                model.update { $0.hosts.append(rewrite) }
                domain = ""
                target = ""
            }
            .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || target.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.profile.rewritesEnabled }, set: { value in model.update { $0.rewritesEnabled = value } })
    }
}
