import ServerControl
import ServiceCatalog
import SwiftUI

/// The service's web address, changeable, with its DNS record
struct SiteAddressRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService
    let onUpdate: (Deployment) -> Void
    @State private var typed = ""
    @State private var report: [String] = []

    private var ingress: WebIngress? { service.webIngress(viewModel.deployment.serviceContext) }
    private var asked: String { SiteAddress.normalized(typed) }

    var body: some View {
        if ServiceSettings.asksHostname(service.id), let ingress {
            VStack(alignment: .leading, spacing: 6) {
                TechnicalField(title: "Site address", prompt: ingress.hostname, text: $typed, ownAddress: true)
                if !asked.isEmpty && !SiteAddress.isValid(asked) {
                    Text("Use letters, digits, hyphens and dots, like music.example.com.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("A name ending in .local works only at home. A new name installs the service again under it and moves its DNS record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(report, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            .id("address-\(service.id.rawValue)")
            .onChange(of: typed) { offerEdit(current: ingress.hostname) }
            if !ingress.homeOnly, viewModel.deployment.scope.publishesAddressRecords {
                SiteDNSControls(viewModel: viewModel, service: service, onUpdate: onUpdate)
            }
        }
    }

    /// Tells the bar whether a new address waits
    private func offerEdit(current: String) {
        let edit = PendingRowEdits.Edit(
            id: "site-address-\(service.id.rawValue)", text: .apply,
            apply: { await move() },
            revert: { typed = "" })
        viewModel.rowEdits.offer(edit, changed: SiteAddress.isValid(asked) && asked != current)
    }

    private func move() async -> Bool {
        let (updated, lines) = await viewModel.moveSite(service, to: asked)
        if let updated { onUpdate(updated) }
        report = lines
        typed = ""
        return updated != nil
    }
}
