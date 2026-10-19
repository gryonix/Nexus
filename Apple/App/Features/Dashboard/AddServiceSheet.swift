import ServerControl
import ServiceCatalog
import SwiftUI

struct AddServiceSheet: View {
    let installed: Set<ServiceID>
    let localOnly: Bool
    var installsAgentFirst = false
    /// Arrays on the server that can hold service data
    var loadArrays: () async -> [StorageArray] = { [] }
    /// The server's memory, when its metrics are in
    var memoryBytes: Int64?
    let onCancel: () -> Void
    /// The services, and the array mount their data goes to
    let onInstall: ([any ManagedService], String?) -> Void

    @State private var selection: Set<ServiceID> = []
    @State private var arrays: [StorageArray] = []
    @State private var askingWhere = false

    /// A warning when the services need more memory
    private var memoryWarning: String? {
        guard let memoryBytes, memoryBytes > 0, !selection.isEmpty else { return nil }
        let needBytes = Int64(ServiceRegistry.requirements(for: installed.union(selection)).memoryMB) * 1_048_576
        guard needBytes > memoryBytes else { return nil }
        let format = ByteCountFormatter()
        format.countStyle = .memory
        return UIL10n.string("These services need about %@ of memory; the server has %@. It may slow down or stop answering.",
                             format.string(fromByteCount: needBytes), format.string(fromByteCount: memoryBytes))
    }

    var body: some View {
        NavigationStack {
            Form {
                if available.isEmpty {
                    Section {
                        Text("Every service this server can run is already installed.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(available, id: \.category) { group in
                        Section(LocalizedStringKey(group.category.title)) {
                            ForEach(group.services, id: \.id) { service in
                                row(service)
                            }
                        }
                    }
                }
                if let warning = memoryWarning {
                    Section {
                        Label(warning, systemImage: "memorychip")
                            .foregroundStyle(.orange)
                    }
                }
                if installsAgentFirst {
                    Section {
                        Label("This server has no gryonixNexus agent yet. It is installed first, then the services.",
                              systemImage: "shippingbox")
                    } footer: {
                        Text("The account the server was added with must be root or allowed to use sudo without a password.")
                    }
                }
                Section {
                    Text("The service is installed by the agent on the server. Its password ends up in the install report, like every other generated credential.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add service")
            .raisedNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install") {
                        if needsPlace { askingWhere = true } else { onInstall(chosen, nil) }
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .confirmationDialog("Where should the data go?", isPresented: $askingWhere,
                                titleVisibility: .visible) {
                ForEach(arrays) { array in
                    Button(UIL10n.string("RAID array %@", array.mountpoint ?? array.name)) {
                        onInstall(chosen, array.mountpoint)
                    }
                }
                Button("Main disk") { onInstall(chosen, nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This server has a RAID array. Files, photos and other data of the new services can live on it instead of the main disk.")
            }
            .task { arrays = await loadArrays() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    private func row(_ service: any ManagedService) -> some View {
        Button {
            toggle(service)
        } label: {
            HStack {
                Label(service.displayName, systemImage: service.systemImage)
                Spacer()
                if selection.contains(service.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The user picks a disk before installing
    private var needsPlace: Bool {
        !arrays.isEmpty && chosen.contains { ServiceSettings.keepsData($0.id) }
    }

    private var chosen: [any ManagedService] {
        ServiceRegistry.all.filter { selection.contains($0.id) }
    }

    private func toggle(_ service: any ManagedService) {
        if selection.contains(service.id) {
            selection.remove(service.id)
            dropOrphanedAddOns()
            return
        }
        if service.category.selection == .exclusive {
            selection = selection.filter { id in
                ServiceRegistry.service(id)?.category != service.category
            }
        }
        selection = selection.filter { !service.conflicts.contains($0) }
        selection.insert(service.id)
    }

    /// Unticking the hub takes its add-ons with it
    private func dropOrphanedAddOns() {
        guard !installed.contains(.homeAssistant), !selection.contains(.homeAssistant) else { return }
        selection.subtract(ServiceID.smartHomeAddOns)
    }

    private var available: [(category: ServiceCategory, services: [any ManagedService])] {
        var order: [ServiceCategory] = []
        var buckets: [ServiceCategory: [any ManagedService]] = [:]
        for service in ServiceRegistry.all where offerable(service) {
            let category = service.category
            if buckets[category] == nil {
                buckets[category] = []
                order.append(category)
            }
            buckets[category, default: []].append(service)
        }
        return order.sorted().map { ($0, buckets[$0] ?? []) }
    }

    private func offerable(_ service: any ManagedService) -> Bool {
        guard service.category != .implicit else { return false }
        guard !installed.contains(service.id) else { return false }
        guard !installed.contains(where: { service.conflicts.contains($0) }) else { return false }
        guard hasItsHub(service) else { return false }
        if localOnly {
            guard service.category != .mail, service.category != .vpn else { return false }
        }
        return true
    }

    /// An add-on is offered only where its hub is
    private func hasItsHub(_ service: any ManagedService) -> Bool {
        guard ServiceID.smartHomeAddOns.contains(service.id) else { return true }
        return installed.contains(.homeAssistant) || selection.contains(.homeAssistant)
    }
}
