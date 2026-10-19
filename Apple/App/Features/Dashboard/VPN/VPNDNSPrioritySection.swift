import AgentControl
import SwiftUI

/// The order the server's DNS relay asks resolvers in
struct VPNDNSPrioritySection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var typing = false
    @State private var typed = ""

    private var priority: VPNDNSPriority? { viewModel.vpnDNSPriority }
    private var local: LocalDNS { LocalDNS(viewModel.vpnDNS) }

    var body: some View {
        if let priority {
            Section {
                ForEach(Array(priority.resolvers.enumerated()), id: \.element) { index, entry in
                    row(index: index, entry: entry, in: priority)
                }
                if VPNDNSPriorityEditing.canAdd(to: priority.resolvers) { addMenu(priority) }
            } header: {
                InfoSectionHeader("DNS order", note: "Devices that use your server's DNS ask these in order. When one does not answer, the next one does — so the internet keeps working while your own resolver is down.")
            } footer: {
                Text("A resolver that stops answering waits at the end of the order for 30 seconds.")
            }
            .alert("Resolver address", isPresented: $typing) {
                TextField(text: $typed) { Text(verbatim: "1.1.1.1") }
                Button("Add") { addTyped() }
                Button("Cancel", role: .cancel) { typed = "" }
            } message: {
                Text("An IPv4 or IPv6 address of a DNS server.")
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
                if !priority.isReachable(at: index) {
                    Text("Not answering").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            rowMenu(index: index, order: priority.resolvers)
        }
    }

    private func rowMenu(index: Int, order: [String]) -> some View {
        Menu {
            Button("Move up") { save(VPNDNSPriorityEditing.moveUp(index, in: order)) }
                .disabled(index == 0)
            Button("Move down") { save(VPNDNSPriorityEditing.moveDown(index, in: order)) }
                .disabled(index == order.count - 1)
            Button("Remove", role: .destructive) { save(VPNDNSPriorityEditing.remove(index, from: order)) }
                .dangerTint()
                .disabled(order.count == 1)
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
            Button("Other address…") { typing = true }
        } label: {
            Label("Add a resolver", systemImage: "plus.circle")
        }
    }

    private func addTyped() {
        defer { typed = "" }
        guard let order = priority?.resolvers, let parsed = PublicDNS.parse(typed), parsed.count == 1 else { return }
        save(VPNDNSPriorityEditing.add(parsed[0], to: order))
    }

    private func save(_ order: [String]) {
        guard order != priority?.resolvers else { return }
        Task { await viewModel.setVPNDNSPriority(order) }
    }
}
