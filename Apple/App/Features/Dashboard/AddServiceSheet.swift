import AgentControl
import AIAssistant
import ServerControl
import ServiceCatalog
import SwiftUI

struct AddServiceSheet: View {
    let deployment: Deployment
    var installsAgentFirst = false
    /// Arrays on the server that can hold service data
    var loadArrays: () async -> [StorageArray] = { [] }
    /// The server's memory, when its metrics are in
    var memoryBytes: Int64?
    /// Asks the machine what it lacks for the services
    var checkMachine: ([ServiceID]) async -> [InstallFinding] = { _ in [] }
    let onCancel: () -> Void
    /// Services, data mount and their settings
    let onInstall: ([any ManagedService], String?, ServiceSettings) -> Void

    @State private var selection: Set<ServiceID> = []
    @State private var arrays: [StorageArray] = []
    @State private var askingWhere = false
    @State private var ollamaModel = OllamaRAM.suggestedModels[0]
    @State private var mount: String?
    @State private var settingUp = false
    @State private var findings: [InstallFinding] = []

    private var installed: Set<ServiceID> { deployment.services }
    private var localOnly: Bool { deployment.scope == .localOnly }

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
                formRows
            }
            .formStyle(.grouped)
            .screenTitle("Add service")
            .raisedNavigationTitle()
            .toolbar { addToolbar }
            .navigationDestination(isPresented: $settingUp) {
                AddServiceSetupStep(services: chosen, deployment: deployment, findings: findings) { settings in
                    onInstall(chosen, mount, settings)
                }
            }
            .confirmationDialog("Where should the data go?", isPresented: $askingWhere,
                                titleVisibility: .visible) {
                ForEach(arrays) { array in
                    Button(UIL10n.string("RAID array %@", array.mountpoint ?? array.name)) {
                        setUp(under: array.mountpoint)
                    }
                }
                Button("Main disk") { setUp(under: nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This server has a RAID array. Files, photos and other data of the new services can live on it instead of the main disk.")
            }
            .task { arrays = await loadArrays() }
            .task(id: selection) {
                findings = selection.isEmpty ? [] : await checkMachine(Array(selection))
                #if DEBUG
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_FINDINGS"] != nil, !selection.isEmpty {
                    findings = [
                        InstallFinding(service: .odio, isBlocking: false, code: "reduced_on_older_os",
                                       args: ["Debian GNU/Linux 12 (bookworm)", "myMPD, disc player, Snapcast, UPnP, Spotify"], message: ""),
                        InstallFinding(service: .mympd, isBlocking: true, code: "needs_newer_os",
                                       args: ["Debian GNU/Linux 12 (bookworm)", "Debian 13"], message: ""),
                    ]
                }
                #endif
            }
            #if DEBUG
            .task { openDemoSetup() }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private var formRows: some View {
    HostCompatibilitySection(findings: findings)
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
    if selection.contains(.ollama) { ollamaAdviceSection }
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

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Next") {
                if needsPlace { askingWhere = true } else { setUp(under: nil) }
            }
            .disabled(selection.isEmpty || !HostCompatibilitySection.blocked(findings).isDisjoint(with: selection))
            .accessibilityIdentifier("addService.next")
        }
    }

    private var ollamaAdviceSection: some View {
        Section {
            Picker("Model you plan to run", selection: $ollamaModel) {
                ForEach(OllamaRAM.suggestedModels, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            if case .tooLow(let need, let have) = OllamaRAM.verdict(model: ollamaModel,
                                                                    machineBytes: memoryBytes.map { UInt64($0) }) {
                Label(UIL10n.string("This model needs about %lld GB of memory; the machine has %lld GB. It may be very slow or fail to load.", need, have),
                      systemImage: "memorychip")
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Rough need: up to 3B parameters 4 GB, 7–8B 8 GB, 13–14B 16 GB, 30B and more 32 GB.")
        }
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

    #if DEBUG
    /// Ticks the listed services and opens their settings
    private func openDemoSetup() {
        if let tick = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TICK"] {
            selection = Set(tick.split(separator: ",").map { ServiceID(rawValue: String($0)) })
            return
        }
        guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ADD_SETUP"] else { return }
        selection = Set(raw.split(separator: ",").map { ServiceID(rawValue: String($0)) })
        setUp(under: nil)
    }
    #endif

    private func setUp(under mount: String?) {
        self.mount = mount
        settingUp = true
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
