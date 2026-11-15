import AgentControl
import SwiftUI

/// The order the server's DNS relay asks resolvers in
struct VPNDNSPrioritySection: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var priority: VPNDNSPriority? { viewModel.vpnDNSPriority }
    private var local: LocalDNS { LocalDNS(viewModel.vpnDNS) }

    var body: some View {
        if let priority {
            Section {
                ForEach(Array(priority.resolvers.enumerated()), id: \.element) { index, entry in
                    row(index: index, entry: entry, in: priority)
                }
                if VPNDNSPriorityEditing.canAdd(to: priority.resolvers) {
                    addMenu(priority)
                    addressRow(priority.resolvers)
                }
            } header: {
                InfoSectionHeader("DNS order", note: "Devices that use your server's DNS ask these in order. When one does not answer, the next one does — so the internet keeps working while your own resolver is down.")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if local.isOffered, priority.resolvers.first != VPNDNSPriority.local {
                        Text("Your server's DNS is not first: devices ask the DNS chosen above before it.")
                            .foregroundStyle(.orange)
                    }
                    Text("A resolver that stops answering waits at the end of the order for 30 seconds.")
                }
            }
        }
    }

    private func row(index: Int, entry: String, in priority: VPNDNSPriority) -> some View {
        HStack {
            Text(verbatim: "\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: VPNDNSPriorityEditing.name(of: entry, local: local))
                if index == 0 {
                    Text("Chosen above, always first").font(.caption).foregroundStyle(.secondary)
                }
                if !priority.isReachable(at: index) {
                    Text("Not answering").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if index == 0 {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Chosen above, always first"))
            } else {
                rowMenu(index: index, order: priority.resolvers)
            }
        }
    }

    private func rowMenu(index: Int, order: [String]) -> some View {
        Menu {
            Button("Move up") { save(VPNDNSPriorityEditing.moveUp(index, in: order)) }
                .disabled(!VPNDNSPriorityEditing.canMoveUp(index))
            Button("Move down") { save(VPNDNSPriorityEditing.moveDown(index, in: order)) }
                .disabled(!VPNDNSPriorityEditing.canMoveDown(index, in: order))
            Button("Remove", role: .destructive) { save(VPNDNSPriorityEditing.remove(index, from: order)) }
                .dangerTint()
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(Text("Change the order"))
        }
        .buttonStyle(.borderless)
    }

    private func addMenu(_ priority: VPNDNSPriority) -> some View {
        Menu {
            if !priority.resolvers.contains(VPNDNSPriority.local) {
                Button(VPNDNSPriorityEditing.name(of: VPNDNSPriority.local, local: local)) {
                    save(VPNDNSPriorityEditing.add(VPNDNSPriority.local, to: priority.resolvers))
                }
            }
            ForEach(VPNDNSPriorityEditing.publicChoices.filter { !priority.resolvers.contains($0.addresses[0]) }) { dns in
                Button(VPNDNSPriorityEditing.name(of: dns.addresses[0], local: local)) {
                    save(VPNDNSPriorityEditing.add(dns.addresses[0], to: priority.resolvers))
                }
            }
        } label: {
            Label("Add a resolver", systemImage: "plus.circle")
        }
    }

    private func addressRow(_ order: [String]) -> some View {
        PendingTextRow(id: "dns-resolver", title: "Resolver address", prompt: "1.1.1.1", saved: "",
                       edits: viewModel.rowEdits, text: .apply, spokenName: false, clearsAfterApply: true,
                       valid: { PublicDNS.parse($0)?.count == 1 }) { typed in
            guard let parsed = PublicDNS.parse(typed), parsed.count == 1 else { return false }
            await viewModel.setVPNDNSPriority(VPNDNSPriorityEditing.add(parsed[0], to: order))
            return true
        }
    }

    private func save(_ order: [String]) {
        guard order != priority?.resolvers else { return }
        Task { await viewModel.setVPNDNSPriority(order) }
    }
}
