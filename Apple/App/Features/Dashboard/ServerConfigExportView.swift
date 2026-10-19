import SwiftUI
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

struct ServerConfigExportView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var dnsZones: [ConfigurationExport.DNSZone] = []
    @State private var ports: ConfigurationExport.PortsBundle?
    @State private var dkim: DKIMState = .idle
    @State private var sortPortsByProtocol = false

    private enum DKIMState {
        case idle, loading, loaded([DKIMRecord]), failed(String)
    }

    private var hasMail: Bool {
        ServiceRegistry.mailEngine(in: viewModel.deployment.services) != nil
    }
    private var entryIsVPS: Bool { viewModel.deployment.hasRelayIngress }

    var body: some View {
        CardList {
            dnsSection
            if hasMail { dkimSection }
            if !publishZones.isEmpty {
                DNSProviderPublishSection(zones: publishZones)
                    .id(loadedDKIM.count)
            }
            portsSection
        }
        .navigationTitle(Text("Configuration"))
        .raisedNavigationTitle()
        .task { await load() }
    }

    // MARK: - Publishing

    /// Every record on this screen, DKIM included, grouped by zone
    private var publishZones: [ServiceConfigViewModel.DNSZonePreview] {
        ConfigurationPublishing.zones(dns: dnsZones, dkim: loadedDKIM,
                                      deployment: viewModel.deployment)
    }

    // MARK: - DNS

    @ViewBuilder
    private var dnsSection: some View {
        if dnsZones.isEmpty {
            Section {
                if viewModel.deployment.domain.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("This server has no domain set, so there are no DNS records to build.")
                        .foregroundStyle(.secondary)
                    Text("Set it in Connection Settings — the “…” menu at the top right.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The DNS records could not be rebuilt from this server's saved configuration.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("DNS records")
            }
        } else {
            ForEach(Array(dnsZones.enumerated()), id: \.element.id) { index, zone in
                Section {
                    RecordShareButtons(copyText: zone.copyText,
                                       zoneFile: zone.zoneFile,
                                       csvFile: zone.csvFile)
                } header: {
                    // "DNS records" once, then the domain per extra zone.
                    if index == 0 {
                        Text("DNS records")
                    } else {
                        Text(verbatim: zone.domain)
                    }
                } footer: {
                    if index == dnsZones.count - 1 {
                        Text("The same records the installation listed. Cloudflare: DNS → Records → “Import and Export” → upload the zone file (it accepts only that one, not the CSV), then set every record to “DNS only” (grey cloud). The CSV is for panels that import a spreadsheet.")
                    }
                }
            }
        }
    }

    // MARK: - DKIM

    private var loadedDKIM: [DKIMRecord] {
        if case .loaded(let records) = dkim { return records }
        return []
    }

    @ViewBuilder
    private var dkimSection: some View {
        Section {
            switch dkim {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading DKIM from the server…").foregroundStyle(.secondary)
                }
            case .loaded(let records):
                if let bundle = DKIMExport.bundle(from: records,
                          zoneSummary: UIL10n.string("DKIM records as a BIND zone file"),
                          csvSummary: UIL10n.string("DKIM records as CSV")) {
                    RecordShareButtons(copyText: bundle.copyText,
                                       zoneFile: bundle.zoneFile,
                                       csvFile: bundle.csvFile)
                } else {
                    Label("The DKIM key was not ready yet.", systemImage: "clock")
                        .font(.callout)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: message).foregroundStyle(.secondary)
                    Button {
                        Task { await loadDKIM() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .rowActionButtonStyle()
                }
            }
        } header: {
            InfoSectionHeader("DKIM records", note: "DKIM is generated on the server by mailcow, so it is fetched live. Without it your outgoing mail is unsigned and most providers treat it as spam.")
        }
    }

    // MARK: - Ports

    @ViewBuilder
    private var portsSection: some View {
        if let ports {
            Section {
                Picker("Sort by", selection: $sortPortsByProtocol) {
                    Text("Port").tag(false)
                    Text("Protocol").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                ForEach(sortPortsByProtocol ? ports.requirements.sortedByProtocol()
                                            : ports.requirements.sortedByPort()) { requirement in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(requirement.port)/\(requirement.proto.rawValue)")
                            .font(.callout.monospaced())
                            .fixedSize()
                        Spacer(minLength: 12)
                        Text(verbatim: requirement.purpose)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                PortsShareButtons(copyText: ports.copyText,
                                  txtFile: ports.txtFile,
                                  csvFile: ports.csvFile)
            } header: {
                InfoSectionHeader(entryIsVPS ? "Ports to open on the VPS" : "Ports to open on the server",
                                  note: "The server configures its own firewall. This list is for the hoster's external firewall (security groups). Export it as a text file or CSV to fill in the provider's form.")
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        let built = ConfigurationExport.build(for: viewModel.deployment)
        dnsZones = built.dns
        ports = built.ports
        if hasMail { await loadDKIM() }
    }

    private func loadDKIM() async {
        dkim = .loading
        do {
            dkim = .loaded(try await viewModel.fetchDKIMRecords())
        } catch {
            dkim = .failed(DashboardViewModel.message(for: error))
        }
    }
}

private struct PortsShareButtons: View {
    let copyText: String
    let txtFile: Artifact
    let csvFile: Artifact

    var body: some View {
        Button {
            copyToClipboard(copyText)
        } label: {
            Label("Copy ports", systemImage: "doc.on.doc")
        }
        .rowActionButtonStyle()
        if let url = RecordShareButtons.artifactURL(txtFile) {
            ShareLink(item: url) {
                Label("Export file (text)", systemImage: "square.and.arrow.up")
            }
        }
        if let url = RecordShareButtons.artifactURL(csvFile) {
            ShareLink(item: url) {
                Label("Export file (CSV)", systemImage: "tablecells")
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
