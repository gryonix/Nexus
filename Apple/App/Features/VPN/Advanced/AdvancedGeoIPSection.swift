import SwiftUI
import VPNProfile

/// Where country networks come from, and their state.
struct AdvancedGeoIPSection: View {
    @ObservedObject var model: AdvancedVPNModel

    var body: some View {
        Section {
            TextField("https://…", text: urlBinding)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            HStack {
                status
                Spacer()
                Button("Refresh") { Task { await model.refreshGeoIP() } }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy || AdvancedGeoIP.codes(in: model.profile.rules).isEmpty)
            }
        } header: {
            InfoSectionHeader("Country database") {
                Text("Only the countries your rules name are kept. They refresh once a week. The default file is v2fly/geoip (CC BY-SA 4.0), made from DB-IP data (CC BY 4.0).")
            }
        }
    }

    @ViewBuilder private var status: some View {
        if model.profile.geoip.updatedAt == nil {
            Text("Not downloaded yet").foregroundStyle(.secondary)
        } else {
            Text("\(model.profile.geoip.ranges.count) countries").foregroundStyle(.secondary)
        }
    }

    private var urlBinding: Binding<String> {
        Binding(get: { model.profile.geoip.url },
                set: { value in model.update { $0.geoip.url = value.trimmingCharacters(in: .whitespaces) } })
    }
}
