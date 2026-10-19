import ServiceCatalog
import SwiftUI

/// The camouflage site picker of a VLESS / Reality device
struct RealitySiteSection: View {
    @Binding var site: String

    private var isListed: Bool { XrayRealityService.suggestedSites.contains(site) }

    var body: some View {
        Section {
            ForEach(XrayRealityService.suggestedSites, id: \.self) { candidate in
                Button {
                    site = candidate
                } label: {
                    HStack {
                        Text(verbatim: candidate)
                        Spacer()
                        if site == candidate { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            TextField("Another site", text: Binding(get: { isListed ? "" : site }, set: { site = $0 }))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
        } header: {
            InfoSectionHeader("Camouflage site", note: "The connection looks like a visit to this site. Pick one that is not blocked where you are. It applies to the whole server; devices added earlier keep working.")
        } footer: {
            if !site.isEmpty, !isListed, XrayRealityService.normalisedSite(site) == nil {
                Text("This is not a site name.")
            }
        }
    }
}
