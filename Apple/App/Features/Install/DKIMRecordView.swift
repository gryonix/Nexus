import gryonixNexusCore
import ServerControl
import SwiftUI

struct DKIMRecordView: View {
    let records: [DKIMRecord]
    var onDone: (() -> Void)?

    private var bundle: DKIMExport.Bundle? { DKIMExport.bundle(from: records,
                          zoneSummary: UIL10n.string("DKIM records as a BIND zone file"),
                          csvSummary: UIL10n.string("DKIM records as CSV")) }

    var body: some View {
        Form {
            Section {
                Label("Add these DNS records to finish setting up mail.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } footer: {
                Text("Until these records exist, your outgoing mail is unsigned and most providers will treat it as spam. This is the last DNS step — the other records were listed before the installation.")
            }

            if let bundle {
                Section {
                    RecordShareButtons(copyText: bundle.copyText,
                                       zoneFile: bundle.zoneFile,
                                       csvFile: bundle.csvFile)
                } header: {
                    InfoSectionHeader("DKIM records", note: "The same records come in three formats: a manual list, a standard BIND zone file, and a generic CSV. Most DNS providers — Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun and others — can import the zone file or the CSV directly, so you don't have to enter every record by hand.")
                }
                DNSProviderPublishSection(zones: DKIMZones.zones(from: records))
            } else {
                Section {
                    Label("The DKIM key was not ready yet.", systemImage: "clock")
                        .font(.callout)
                } footer: {
                    Text("mailcow generates it shortly after the first start. Open mailcow's own admin panel at mail.<your domain> in a few minutes — the record is under Configuration → ARC/DKIM keys.")
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("DKIM records")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .prominentActionButtonStyle()
                }
            }
        }
    }
}
