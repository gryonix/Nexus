import ServerControl
import ServiceCatalog
import SwiftUI

struct HomeOnlyRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService
    let onUpdate: (Deployment) -> Void
    @State private var applying = false
    @State private var draft = HomeOnlyDraft()

    var body: some View {
        if viewModel.offersHomeOnly(service) {
            VStack(alignment: .leading, spacing: 10) {
                homeOnlyToggle
                failureLine
                if viewModel.isHomeOnly(service.id) {
                    if hasWebSite { noVPNToggle }
                    if let host = service.webIngress(viewModel.deployment.serviceContext)?.hostname {
                        HomeLocalNameToggle(viewModel: viewModel, host: host)
                        HomeOnlyReachLine(host: host)
                    }
                    PublicPortsStatus(viewModel: viewModel, service: service)
                }
            }
            .onChange(of: draft) { offerEdit() }
        }
    }

    /// Tells the bar whether the switches wait
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "home-only-\(service.id.rawValue)", text: .apply,
            apply: { await applyDraft(field.wrappedValue) },
            revert: { field.wrappedValue = HomeOnlyDraft() })
        viewModel.rowEdits.offer(edit, changed: waits(draft))
    }

    private func waits(_ asked: HomeOnlyDraft) -> Bool {
        asked.waits(homeOnly: viewModel.isHomeOnly(service.id), noVPN: viewModel.isNoVPN(service.id))
    }

    /// Applies the waiting switches; false when one failed
    private func applyDraft(_ asked: HomeOnlyDraft) async -> Bool {
        applying = true
        if let wanted = asked.homeOnly, wanted != viewModel.isHomeOnly(service.id) {
            onUpdate(await viewModel.setHomeOnly(service, wanted))
        }
        if let wanted = asked.noVPN, viewModel.isHomeOnly(service.id), wanted != viewModel.isNoVPN(service.id) {
            onUpdate(await viewModel.setNoVPN(service, wanted))
        }
        applying = false
        draft = HomeOnlyDraft()
        return viewModel.homeOnlyFailures[service.id] == nil
    }

    private var hasWebSite: Bool {
        service.webIngress(viewModel.deployment.serviceContext) != nil
    }

    /// Applies the switch, showing progress meanwhile
    private func apply(_ wanted: Bool) {
        applying = true
        Task {
            onUpdate(await viewModel.setHomeOnly(service, wanted))
            applying = false
        }
    }

    @ViewBuilder
    private var failureLine: some View {
        if let failure = viewModel.homeOnlyFailures[service.id], !applying {
            HStack(alignment: .top) {
                Text(verbatim: failure)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Try again") { apply(viewModel.isHomeOnly(service.id)) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
        }
    }

    private var homeOnlyToggle: some View {
        Toggle(isOn: Binding(
            get: { draft.homeOnly ?? viewModel.isHomeOnly(service.id) },
            set: { draft.homeOnly = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Only at home")
                    if applying { ProgressView().controlSize(.small) }
                }
                Text("Closed from the internet; works in your home network and over your VPN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(applying)
    }

    private var noVPNToggle: some View {
        Toggle(isOn: Binding(
            get: { !(draft.noVPN ?? viewModel.isNoVPN(service.id)) },
            set: { draft.noVPN = !$0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Also over our VPN")
                Text("Turn off to keep VPN clients out too; only your home network gets in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(applying)
        .padding(.leading, 16)
    }
}

/// Home-only switches that wait to be applied
struct HomeOnlyDraft: Equatable {
    var homeOnly: Bool?
    var noVPN: Bool?

    /// Whether a switch differs from the server
    func waits(homeOnly saved: Bool, noVPN savedNoVPN: Bool) -> Bool {
        let home = homeOnly.map { $0 != saved } ?? false
        let vpn = noVPN.map { $0 != savedNoVPN } ?? false
        return home || vpn
    }
}

/// What the relay found open from outside
private struct PublicPortsStatus: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService

    var body: some View {
        if let verdict = viewModel.publicPortVerdicts[service.id] {
            HStack {
                switch verdict {
                case .closed:
                    Text("Closed from the internet ✓")
                        .foregroundStyle(.green)
                case .open(let ports):
                    Text(UIL10n.string("Still open from the internet on: %@",
                                       ports.map(String.init).joined(separator: ", ")))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Check again") { Task { await viewModel.probePublicPorts(of: service) } }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .padding(.leading, 16)
        }
    }
}

struct SiteDNSControls: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService
    let onUpdate: (Deployment) -> Void
    @State private var busy = false
    @State private var report: [String] = []
    @State private var manual: HomeOnlyDNS.Manual?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(removed ? "Restore DNS record" : "Remove public DNS record") { run(removed ? .restore : .remove) }
                .disabled(busy)
            Text(viewModel.isHomeOnly(service.id)
                 ? "Removing the record only hides the site; the guard is what keeps it closed."
                 : "The record points this name at the server. Without it the site cannot be found from the internet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(report, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.leading, 16)
        .sheet(item: $manual) { pending in
            DNSByHandSheet(manual: pending) {
                onUpdate(viewModel.markDNSRemoved(service, pending.action == .remove))
                manual = nil
            }
        }
    }

    private var removed: Bool { viewModel.isDNSRemoved(service.id) }

    private func run(_ action: HomeOnlyDNS.Action) {
        busy = true
        report = []
        Task {
            let outcome = await HomeOnlyDNS.change(action, service, in: viewModel.deployment)
            switch outcome {
            case .done(let lines):
                report = lines
                onUpdate(viewModel.markDNSRemoved(service, action == .remove))
            case .failed(let lines):
                report = lines
            case .manual(let instructions):
                manual = instructions
            }
            busy = false
        }
    }
}

extension HomeOnlyDNS.Manual: Identifiable {
    var id: String { lines.joined(separator: "|") + (action == .remove ? "-" : "+") }
}

private struct DNSByHandSheet: View {
    let manual: HomeOnlyDNS.Manual
    let done: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(manual.action == .remove
                         ? "Remove these records at your DNS provider, then tap Done."
                         : "Add these records at your DNS provider, then tap Done.")
                }
                Section {
                    ForEach(manual.lines, id: \.self) { Text($0).font(.body.monospaced()).textSelection(.enabled) }
                }
            }
            .navigationTitle("Change the DNS record by hand")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
    }
}

/// Offers the server's own root certificate to this device
struct InternalCertificateRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        if viewModel.deployment.scope.usesInternalTLS {
            VStack(alignment: .leading, spacing: 6) {
                Button("Trust this server's certificate on this device", action: install)
                    .disabled(busy)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func install() {
        busy = true
        note = nil
        Task {
            do {
                let pem = try await viewModel.fetchLocalRootCA()
                guard let profile = InternalCertificateProfile.mobileconfig(
                    pem: pem, serverName: viewModel.deployment.name) else {
                    throw ServerControlError.notConfigured(UIL10n.string("This server has no certificate of its own yet."))
                }
                let step = try await ProfileInstaller.install(profile, fileName: "\(viewModel.deployment.name)-root-ca.mobileconfig")
                note = step == .openSettings
                    ? UIL10n.string("Open Settings, tap Profile Downloaded, install it, then switch it on under General › About › Certificate Trust Settings.")
                    : UIL10n.string("Confirm the install in the prompt, then set the certificate to Always Trust in Keychain Access.")
            } catch {
                note = error.localizedDescription
            }
            busy = false
        }
    }
}

/// The site's second name, answered on the home network
private struct HomeLocalNameToggle: View {
    @ObservedObject var viewModel: DashboardViewModel
    let host: String
    @State private var alias: String?
    @State private var loaded = false
    @State private var error: String?
    @State private var draft: Bool?

    private var proposed: String { (host.split(separator: ".").first.map(String.init) ?? host) + ".local" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { draft ?? (alias != nil) }, set: { draft = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UIL10n.string("Name at home: %@", proposed))
                    Text("Phones and computers at home open it by this name, without the internet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!loaded)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(.leading, 16)
        .task { await load() }
        .onChange(of: draft) { offerEdit() }
    }

    private func load() async {
        alias = (try? await viewModel.localAliases())?[host]
        loaded = true
    }

    /// Tells the bar whether the name waits
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "local-name-\(host)", text: .apply,
            apply: {
                guard let wanted = field.wrappedValue else { return true }
                let done = await change(wanted)
                field.wrappedValue = nil
                return done
            },
            revert: { field.wrappedValue = nil })
        viewModel.rowEdits.offer(edit, changed: draft.map { $0 != (alias != nil) } ?? false)
    }

    /// Sets the name; false when the server refused
    private func change(_ on: Bool) async -> Bool {
        loaded = false
        defer { loaded = true }
        do {
            alias = try await viewModel.localAliases(setting: host, on: on)[host]
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
