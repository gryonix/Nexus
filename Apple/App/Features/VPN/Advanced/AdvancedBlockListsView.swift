import SwiftUI
import VPNProfile

/// Domain lists that are blocked.
struct AdvancedBlockListsView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var address = ""

    var body: some View {
        Form {
            Section {
                ForEach(model.profile.blockLists) { list in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: list.url).lineLimit(1)
                            Text("\(list.domains.count) domains").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh") { Task { await model.refreshBlockList(list.id) } }
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in model.update { $0.blockLists.remove(atOffsets: offsets) } }
            } header: {
                InfoSectionHeader("Block lists") {
                    Text("A list of domains, one per line, or a hosts file. Up to 15000 domains per list. Matching domains are blocked.")
                }
            }
            Section {
                TextField("https://…", text: $address)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Button("Add list") { Task { await model.addBlockList(address); address = "" } }
                    .disabled(address.isEmpty || model.isBusy)
            }
        }
        .formStyle(.grouped)
        .screenTitle("Block lists")
    }
}
