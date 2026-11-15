import SwiftUI
import VPNProfile

/// Adds subscriptions and pasted lists or Clash profiles.
struct AdvancedImportView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var address = ""
    @State private var pasted = ""

    var body: some View {
        Form {
            subscriptionSection
            Section {
                TextEditor(text: $pasted)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                Button("Import") { model.importText(pasted); pasted = "" }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                InfoSectionHeader("Paste links or a Clash profile") {
                    Text("vless, vmess, trojan, ss, hysteria2 and naive+https links, a base64 list of them, or a Clash YAML with proxies and rules.")
                }
            }
            if let report = model.report { AdvancedReportSection(report: report) }
        }
        .formStyle(.grouped)
        .screenTitle("Import")
    }

    private var subscriptionSection: some View {
        Section {
            ForEach(model.profile.subscriptions) { subscription in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: subscription.name)
                        Text("\(subscription.serverIDs.count) servers").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { Task { await model.refresh(subscription.id) } }
                        .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                let gone = offsets.map { model.profile.subscriptions[$0] }
                model.update { profile in
                    for subscription in gone {
                        profile = profile.removing(serverIDs: Set(subscription.serverIDs))
                        profile.subscriptions.removeAll { $0.id == subscription.id }
                    }
                }
            }
            TextField("https://…", text: $address)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button("Add subscription") {
                Task { await model.addSubscription(address); address = "" }
            }
            .disabled(address.isEmpty || model.isBusy)
        } header: {
            InfoSectionHeader("Subscriptions") {
                Text("A link that returns a list of servers. It refreshes once a day when you open this screen, or on demand.")
            }
        }
    }
}

struct AdvancedReportSection: View {
    let report: AdvancedImportReport

    var body: some View {
        Section("Import report") {
            Text("\(report.servers.count) servers, \(report.rules.count) rules")
            ForEach(Array(report.unsupported.enumerated()), id: \.offset) { _, skipped in
                VStack(alignment: .leading) {
                    Text(verbatim: skipped.name).lineLimit(1)
                    Text(verbatim: skipped.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !report.unsupported.isEmpty {
                Text("Unsupported items were left out.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
