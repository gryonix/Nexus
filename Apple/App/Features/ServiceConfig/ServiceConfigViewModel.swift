import Combine
import Foundation
import MailRecipe
import SwiftUI
import gryonixNexusCore
import ServerControl
import ServiceCatalog

/// Collects the service-configuration form input and drives the core's validation/generation
@MainActor
final class ServiceConfigViewModel: ObservableObject {
    let topology: Topology

    @Published var domain = ""
    /// PTR target for outgoing mail; empty — relay.<domain>
    @Published var reverseDNSHostname = ""
    /// Further domains the same server answers on
    @Published var additionalDomains: [String] = []
    @Published var scope: DeploymentScope = .publicInternet
    var localOnly: Bool { scope == .localOnly }
    @Published var publicIP = ""                 // A: server IP; B: VPS IP
    @Published var vpsVPNIP = "10.8.0.1"
    @Published var homeVPNIP = "10.8.0.2"
    /// The local server as this device reaches it
    @Published var homeNetworkAddress = ""
    /// Scenario A — the one server; scenario B — the VPS relay
    @Published var distribution: DistributionProfileID = .debian
    /// Scenario B only
    @Published var homeDistribution: DistributionProfileID = .debian

    // MARK: Services

    @Published var mailEnabled = false
    /// Which engine the mail toggle installs
    @Published var mailEngine: ServiceID = .mailcow
    /// Services selected beyond the mail stack
    @Published var extraServices: Set<ServiceID> = []
    @Published var vpnEnabled = false
    @Published var vpnProtocols: Set<ServiceID> = []

    @Published var serviceHostnames: [ServiceID: String] = [:]
    @Published var vaultwardenAllowSignups = false
    /// Which services single sign-on stands in front of
    @Published var autheliaProtectedServices: Set<ServiceID> = AutheliaService.defaultProtected

    @Published var piholeServesNetwork = false
    // The AI shelf.
    /// WHERE the models this deployment talks to actually run
    @Published var modelBackend = ServiceSettings().modelBackend
    @Published var ollamaUsesGPU = ServiceSettings().ollamaUsesGPU
    @Published var ollamaInstallsGPUDriver = ServiceSettings().ollamaInstallsGPUDriver
    /// Open registration on the chat
    @Published var openWebUIAllowSignups = ServiceSettings().openWebUIAllowSignups
    @Published var minecraftJavaAcceptsEULA = false
    @Published var minecraftJavaVersion = ""
    @Published var minecraftJavaFlavour = ServiceSettings().minecraftJavaFlavour
    @Published var minecraftJavaMemoryMB = "\(ServiceSettings().minecraftJavaMemoryMB)"
    @Published var minecraftJavaPort = "\(ServiceSettings().minecraftJavaPort)"
    @Published var minecraftJavaWhitelist = ""
    @Published var minecraftJavaOperators = ""
    /// What the mod browser picked, in `MODRINTH_PROJECTS` syntax
    @Published var minecraftJavaMods = ""
    @Published var minecraftBedrockAcceptsEULA = false
    @Published var machineAtHome = false
    @Published var homeAssistantUSBDevice = ""
    /// The server this run is re-configuring, when there is one
    let existingServer: Deployment?
    @Published var serialListing: SerialListing = .idle
    @Published var minecraftBedrockVersion = ""
    @Published var minecraftBedrockPort = "\(ServiceSettings().minecraftBedrockPort)"
    @Published var forgejoSSHPort: String = "\(ServiceSettings().forgejoSSHPort)"
    @Published var gitlabSSHPort: String = "\(ServiceSettings().gitlabSSHPort)"

    @Published var adminUsername = "admin"
    /// One hostname for the whole VPN, whichever protocol is chosen
    @Published var vpnHostname = ""
    @Published var vpnClientAccess: VPNClientAccess = .both
    /// Kept as text (form fields); parsed and validated on generation
    @Published var wireguardVPNPort: String
    @Published var amneziaWGPort: String
    @Published var shadowsocksPort: String = "\(ServiceSettings().shadowsocksPort)"
    @Published var xrayRealityPort: String = "\(ServiceSettings().xrayRealityPort)"
    @Published var xrayRealitySNI: String = ServiceSettings().xrayRealitySNI
    @Published var openVPNPort: String = "\(ServiceSettings().openVPNPort)"

    @Published var includeDashboardAccess = false
    /// Recommended, not required — see `ServiceSettings.crowdsecEnabled`
    @Published var crowdsecEnabled = ServiceSettings().crowdsecEnabled
    @Published var dashboardSSHUser = DashboardAccessInput.defaultUser
    @Published var useExistingUser = false
    /// Existing user's password
    @Published var existingUserPassword = ""
    /// The home half's own password, on a scenario-B pair
    @Published var existingUserHomePassword = ""

    @Published var errorMessage: String?
    @Published var bundle: GeneratedBundle?
    @Published var openPorts: [OpenPortRequirement] = []
    /// Deployment saved to the server list after successful generation
    @Published var savedDeployment: Deployment?

    private(set) var deploymentID = UUID()

    private var pendingPasswordDeploymentID: UUID?

    private let pinsDeploymentID: Bool

    private var reinstallOriginalDomain: String?
    private var domainChangeConfirmed = false
    private var erasesMailOnDomainChange = false
    /// Drives the confirmation alert on the reinstall screens
    @Published var pendingDomainChange = false

    /// The generator's ceiling on additional domains
    var isPairTopology: Bool { topology == .vpsRelayWithHomeBackend }

    var canAddDomain: Bool { additionalDomains.count < MailInputValidator.maxAdditionalDomains }

    var reinstallChangesDomain: Bool {
        guard let original = reinstallOriginalDomain else { return false }
        return Self.normalizedDomain(domain) != Self.normalizedDomain(original)
            && !Self.normalizedDomain(domain).isEmpty
    }

    var reinstallRecreatesMail: Bool { reinstallChangesDomain && mailEnabled }

    var reinstallPreviousDomain: String { reinstallOriginalDomain ?? "" }

    private static func normalizedDomain(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Confirms the domain change and continues with generation
    func confirmDomainChangeAndGenerate(erasingMail: Bool) async {
        domainChangeConfirmed = true
        erasesMailOnDomainChange = erasingMail
        await generate()
    }

    private let injectedIdentityStore: (any SSHIdentityStore)?

    func prefillStoredPassword() async {
        guard let id = pendingPasswordDeploymentID else { return }
        pendingPasswordDeploymentID = nil
        let stored = await Task.detached(priority: .userInitiated) {
            let store = DashboardPasswordStore(deploymentID: id)
            return (store.load(for: .vps), store.load(for: .home))
        }.value
        if let entry = stored.0, existingUserPassword.isEmpty { existingUserPassword = entry }
        if let home = stored.1, existingUserHomePassword.isEmpty { existingUserHomePassword = home }
    }

    /// Whether the stick can be read off the machine
    var canListSerialDevices: Bool {
        guard #available(macOS 15.0, *) else { return false }
        guard let existingServer else { return false }
        return existingServer.usesAgent
    }

    func loadSerialDevices() async {
        guard #available(macOS 15.0, *), let existingServer, existingServer.usesAgent else { return }
        serialListing = .loading
        let listing = await SerialDevices.list(deployment: existingServer)
        if let failure = listing.failure {
            serialListing = .failed(failure)
        } else {
            serialListing = .loaded(listing.devices, directoryPresent: listing.directoryPresent)
        }
    }

    private func loadIdentity() async throws -> AppSSHIdentity {
        if let injectedIdentityStore { return try injectedIdentityStore.loadOrGenerate() }
        let deploymentID = deploymentID
        return try await Task.detached(priority: .userInitiated) {
            try KeychainSSHIdentityStore(deploymentID: deploymentID).loadOrGenerate()
        }.value
    }
    private let deploymentStore: any DeploymentStore
    private let configuratorStore: ConfiguratorStore
    private var autosave: AnyCancellable?

    static let extraServiceChoices: [ServiceID] = [.vaultwarden, .nextcloud, .immich, .forgejo, .gitlab]
    /// VPN protocols offered under the VPN row, in catalog order
    static let allVPNProtocols: [ServiceID] = [.wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN]

    // MARK: - Category-driven selection

    /// Categories offered for selection
    var availableCategories: [ServiceCategory] {
        guard !scope.carriesNonWebServices else { return ServiceRegistry.categories }
        return ServiceRegistry.categories.filter { category in
            category.id != ServiceCategory.vpn.id
                && ServiceRegistry.services(in: category).contains { !$0.requiresPublicDomain }
        }
    }

    /// What this form currently installs from one category
    func selection(in category: ServiceCategory) -> Set<ServiceID> {
        switch category.id {
        case ServiceCategory.mail.id:
            return mailEnabled ? [mailEngine] : []
        case ServiceCategory.vpn.id:
            return vpnEnabled ? vpnProtocols : []
        default:
            return extraServices.intersection(ServiceRegistry.ids(in: category))
        }
    }

    func setSelectionPublic(_ ids: Set<ServiceID>, in category: ServiceCategory) {
        setSelection(ids, in: category)
    }

    private func setSelection(_ ids: Set<ServiceID>, in category: ServiceCategory) {
        switch category.id {
        case ServiceCategory.mail.id:
            mailEnabled = !ids.isEmpty
            if let engine = ids.first { mailEngine = engine }
        case ServiceCategory.vpn.id:
            vpnEnabled = !ids.isEmpty
            vpnProtocols = ids
        default:
            extraServices.subtract(ServiceRegistry.ids(in: category))
            extraServices.formUnion(ids)
        }
    }

    func defaultMember(of category: ServiceCategory) -> ServiceID? {
        ServiceRegistry.services(in: category).first?.id
    }

    /// A whole category on/off
    func categoryBinding(_ category: ServiceCategory) -> Binding<Bool> {
        Binding(
            get: { !self.selection(in: category).isEmpty },
            set: { on in
                guard on else {
                    self.setSelection([], in: category)
                    return
                }
                guard self.selection(in: category).isEmpty,
                      let fallback = self.defaultMember(of: category) else { return }
                self.setSelection([fallback], in: category)
            }
        )
    }

    /// The one member an exclusive (or simple-mode) category installs
    func categoryEngineBinding(_ category: ServiceCategory) -> Binding<ServiceID> {
        Binding(
            get: {
                self.selection(in: category).first
                    ?? self.defaultMember(of: category)
                    ?? .mailcow
            },
            set: { self.setSelection([$0], in: category) }
        )
    }

    var autheliaCandidates: [ServiceID] {
        let context = ServiceContext(domain: domain.isEmpty ? "example.com" : domain,
                                     sshUser: "", settings: makeServiceSettings(),
                                     installedServices: selectedServices)
        return ServiceRegistry.services(selectedServices)
            .filter { $0.id != .authelia && $0.webIngress(context) != nil }
            // The mesh control server is not a choice — see `AutheliaService.neverProtected`.
            .filter { !AutheliaService.neverProtected.contains($0.id) }
            .map(\.id)
    }

    func autheliaProtectionBinding(_ id: ServiceID) -> Binding<Bool> {
        Binding(
            get: { self.autheliaProtectedServices.contains(id) },
            set: { on in
                if on { self.autheliaProtectedServices.insert(id) }
                else { self.autheliaProtectedServices.remove(id) }
            }
        )
    }

    func serviceBinding(_ id: ServiceID) -> Binding<Bool> {
        guard let category = ServiceRegistry.service(id)?.category else {
            return .constant(false)
        }
        return Binding(
            get: { self.selection(in: category).contains(id) },
            set: { on in
                var ids = self.selection(in: category)
                if on { ids.insert(id) } else { ids.remove(id) }
                if on, category.selection == .exclusive { ids = [id] }
                self.setSelection(ids, in: category)
            }
        )
    }

    /// One service's own hostname field
    func hostnameBinding(_ id: ServiceID) -> Binding<String> {
        Binding(
            get: { self.serviceHostnames[id] ?? "" },
            set: { self.serviceHostnames[id] = $0 }
        )
    }

    /// One required question's answer
    func questionBinding(_ question: ServiceQuestion) -> Binding<Bool> {
        switch question {
        case .minecraftJavaEULA:
            return Binding(get: { self.minecraftJavaAcceptsEULA },
                           set: { self.minecraftJavaAcceptsEULA = $0 })
        case .minecraftBedrockEULA:
            return Binding(get: { self.minecraftBedrockAcceptsEULA },
                           set: { self.minecraftBedrockAcceptsEULA = $0 })
        case .machineAtHome:
            return Binding(get: { self.machineAtHome }, set: { self.machineAtHome = $0 })
        }
    }

    func isAnswered(_ question: ServiceQuestion) -> Bool {
        questionBinding(question).wrappedValue
    }

    /// Binding for one protocol's on/off state in the multi-select
    func vpnProtocolBinding(_ id: ServiceID) -> Binding<Bool> {
        serviceBinding(id)
    }

    /// Are all five VPN protocols on?
    var allVPNProtocolsSelected: Bool {
        Set(Self.allVPNProtocols).isSubset(of: selection(in: .vpn))
    }

    /// Turn every protocol on, or leave only the default one
    func setAllVPNProtocols(_ on: Bool) {
        if on {
            setSelectionPublic(Set(Self.allVPNProtocols), in: .vpn)
        } else if let fallback = defaultMember(of: .vpn) {
            setSelectionPublic([fallback], in: .vpn)
        }
    }

    /// Is every service that CAN be guarded actually guarded?
    var allAutheliaCandidatesProtected: Bool {
        let candidates = Set(autheliaCandidates)
        return !candidates.isEmpty && candidates.isSubset(of: autheliaProtectedServices)
    }

    func setAllAutheliaProtection(_ on: Bool) {
        autheliaProtectedServices = on ? Set(autheliaCandidates)
                                       : AutheliaService.defaultProtected
    }

    init(topology: Topology,
         initialScope: DeploymentScope = .publicInternet,
         identityStore: (any SSHIdentityStore)? = nil,
         deploymentStore: any DeploymentStore = FileDeploymentStore(),
         configuratorStore: ConfiguratorStore = .shared,
         restoringConfig: ConfiguratorDraft? = nil,
         existingServer: Deployment? = nil) {
        self.topology = topology
        self.existingServer = existingServer
        self.injectedIdentityStore = identityStore
        self.deploymentStore = deploymentStore
        self.configuratorStore = configuratorStore
        self.pinsDeploymentID = restoringConfig != nil
        self.wireguardVPNPort = topology == .vpsRelayWithHomeBackend ? "51821" : "51820"
        self.amneziaWGPort = "\(ServiceSettings().amneziaWGPort)"
        if let restoringConfig {
            apply(restoringConfig)
            homeNetworkAddress = restoringConfig.deploymentID.map { InstallAddressStore.homeAddress(deploymentID: $0) } ?? ""
            reinstallOriginalDomain = restoringConfig.domain
            if restoringConfig.useExistingUser {
                pendingPasswordDeploymentID = restoringConfig.deploymentID
            }
            return
        }
        self.scope = initialScope
        if let draft = configuratorStore.loadDraft(for: topology, scope: initialScope) {
            apply(draft)
        } else if let remembered = configuratorStore.lastDashboardUser {
            dashboardSSHUser = remembered
        }
        autosave = objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.configuratorStore.saveDraft(self.snapshot())
                self.configuratorStore.lastDashboardUser = self.dashboardSSHUser
            }
    }

    // MARK: - Draft & history

    func snapshot() -> ConfiguratorDraft {
        var draft = ConfiguratorDraft(topology: topology)
        draft.domain = domain
        draft.reverseDNSHostname = reverseDNSHostname
        draft.additionalDomains = additionalDomains
        draft.localOnly = localOnly
        draft.scope = scope
        draft.publicIP = publicIP
        draft.vpsVPNIP = vpsVPNIP
        draft.homeVPNIP = homeVPNIP
        draft.distribution = distribution.rawValue
        draft.homeDistribution = homeDistribution.rawValue
        draft.mailEnabled = mailEnabled
        draft.mailEngineID = mailEngine.rawValue
        draft.extraServices = extraServices
        draft.vpnEnabled = vpnEnabled
        draft.vpnProtocols = vpnProtocols
        draft.setHostnames(serviceHostnames)
        draft.vaultwardenAllowSignups = vaultwardenAllowSignups
        draft.piholeServesNetwork = piholeServesNetwork
        draft.modelBackend = modelBackend.rawValue
        draft.ollamaUsesGPU = ollamaUsesGPU
        draft.ollamaInstallsGPUDriver = ollamaInstallsGPUDriver
        draft.openWebUIAllowSignups = openWebUIAllowSignups
        draft.minecraftJavaAcceptsEULA = minecraftJavaAcceptsEULA
        draft.minecraftJavaVersion = minecraftJavaVersion
        draft.minecraftJavaFlavour = minecraftJavaFlavour
        draft.minecraftJavaMemoryMB = minecraftJavaMemoryMB
        draft.minecraftJavaPort = minecraftJavaPort
        draft.minecraftJavaWhitelist = minecraftJavaWhitelist
        draft.minecraftJavaOperators = minecraftJavaOperators
        draft.minecraftJavaMods = minecraftJavaMods
        draft.minecraftBedrockAcceptsEULA = minecraftBedrockAcceptsEULA
        draft.machineAtHome = machineAtHome
        draft.homeAssistantUSBDevice = homeAssistantUSBDevice
        draft.minecraftBedrockVersion = minecraftBedrockVersion
        draft.minecraftBedrockPort = minecraftBedrockPort
        draft.autheliaProtectedServices = autheliaProtectedServices
        draft.adminUsername = adminUsername
        draft.forgejoSSHPort = forgejoSSHPort
        draft.gitlabSSHPort = gitlabSSHPort
        draft.vpnHostname = vpnHostname
        draft.vpnClientAccess = vpnClientAccess.rawValue
        draft.wireguardVPNPort = wireguardVPNPort
        draft.amneziaWGPort = amneziaWGPort
        draft.shadowsocksPort = shadowsocksPort
        draft.xrayRealityPort = xrayRealityPort
        draft.xrayRealitySNI = xrayRealitySNI
        draft.openVPNPort = openVPNPort
        draft.includeDashboardAccess = includeDashboardAccess
        draft.crowdsecEnabled = crowdsecEnabled
        draft.dashboardSSHUser = dashboardSSHUser
        draft.useExistingUser = useExistingUser
        draft.deploymentID = deploymentID
        return draft
    }

    /// Fills the form from a draft or history entry
    func apply(_ draft: ConfiguratorDraft) {
        domain = draft.domain
        reverseDNSHostname = draft.reverseDNSHostname
        additionalDomains = draft.additionalDomains
        scope = draft.scope ?? (draft.localOnly ? .localOnly : .publicInternet)
        publicIP = draft.publicIP
        vpsVPNIP = draft.vpsVPNIP
        homeVPNIP = draft.homeVPNIP
        distribution = draft.entryDistribution
        homeDistribution = draft.homeDistributionID
        mailEnabled = draft.mailEnabled
        mailEngine = ServiceID(rawValue: draft.mailEngineID)
        extraServices = draft.extraServices
        vpnProtocols = draft.vpnProtocols
        vpnEnabled = draft.vpnEnabled && !draft.vpnProtocols.isEmpty
        serviceHostnames = draft.resolvedHostnames
        vaultwardenAllowSignups = draft.vaultwardenAllowSignups
        piholeServesNetwork = draft.piholeServesNetwork ?? piholeServesNetwork
        modelBackend = draft.modelBackend.flatMap(ModelBackend.init(rawValue:)) ?? modelBackend
        ollamaUsesGPU = draft.ollamaUsesGPU ?? ollamaUsesGPU
        ollamaInstallsGPUDriver = draft.ollamaInstallsGPUDriver ?? ollamaInstallsGPUDriver
        openWebUIAllowSignups = draft.openWebUIAllowSignups ?? openWebUIAllowSignups
        minecraftJavaAcceptsEULA = draft.minecraftJavaAcceptsEULA ?? minecraftJavaAcceptsEULA
        minecraftJavaVersion = draft.minecraftJavaVersion ?? minecraftJavaVersion
        minecraftJavaFlavour = draft.minecraftJavaFlavour ?? minecraftJavaFlavour
        minecraftJavaMemoryMB = draft.minecraftJavaMemoryMB ?? minecraftJavaMemoryMB
        minecraftJavaPort = draft.minecraftJavaPort ?? minecraftJavaPort
        minecraftJavaWhitelist = draft.minecraftJavaWhitelist ?? minecraftJavaWhitelist
        minecraftJavaOperators = draft.minecraftJavaOperators ?? minecraftJavaOperators
        minecraftJavaMods = draft.minecraftJavaMods ?? minecraftJavaMods
        minecraftBedrockAcceptsEULA = draft.minecraftBedrockAcceptsEULA ?? minecraftBedrockAcceptsEULA
        machineAtHome = draft.machineAtHome ?? machineAtHome
        homeAssistantUSBDevice = draft.homeAssistantUSBDevice ?? homeAssistantUSBDevice
        minecraftBedrockVersion = draft.minecraftBedrockVersion ?? minecraftBedrockVersion
        minecraftBedrockPort = draft.minecraftBedrockPort ?? minecraftBedrockPort
        autheliaProtectedServices = draft.autheliaProtectedServices ?? autheliaProtectedServices
        adminUsername = draft.adminUsername
        forgejoSSHPort = draft.forgejoSSHPort.isEmpty ? forgejoSSHPort : draft.forgejoSSHPort
        gitlabSSHPort = draft.gitlabSSHPort.isEmpty ? gitlabSSHPort : draft.gitlabSSHPort
        vpnHostname = draft.vpnHostname
        vpnClientAccess = draft.vpnClientAccess.flatMap(VPNClientAccess.init(rawValue:)) ?? .both
        wireguardVPNPort = draft.wireguardVPNPort.isEmpty ? wireguardVPNPort : draft.wireguardVPNPort
        amneziaWGPort = draft.amneziaWGPort.isEmpty ? amneziaWGPort : draft.amneziaWGPort
        shadowsocksPort = draft.shadowsocksPort.isEmpty ? shadowsocksPort : draft.shadowsocksPort
        xrayRealityPort = draft.xrayRealityPort.isEmpty ? xrayRealityPort : draft.xrayRealityPort
        xrayRealitySNI = draft.xrayRealitySNI.isEmpty ? xrayRealitySNI : draft.xrayRealitySNI
        openVPNPort = draft.openVPNPort.isEmpty ? openVPNPort : draft.openVPNPort
        includeDashboardAccess = draft.includeDashboardAccess
        crowdsecEnabled = draft.crowdsecEnabled ?? crowdsecEnabled
        if !draft.dashboardSSHUser.isEmpty { dashboardSSHUser = draft.dashboardSSHUser }
        useExistingUser = draft.useExistingUser
        if let id = draft.deploymentID { deploymentID = id }
    }

    func historyEntries() -> [ConfiguratorDraft] {
        configuratorStore.history()
    }

    func deleteHistoryEntries(ids: Set<UUID>) {
        configuratorStore.deleteFromHistory(ids: ids)
    }

    var selectedServices: Set<ServiceID> {
        var services = extraServices
        if mailEnabled { services.insert(mailEngine) }
        if vpnEnabled { services.formUnion(vpnProtocols) }
        return ServiceRegistry.expanded(services, scope: scope, modelBackend: modelBackend)
    }

    var hasAdminService: Bool {
        ServiceRegistry.services(selectedServices).contains { $0.usesSharedAdminLogin }
    }

    var hostnamePlaceholder: String {
        domain.isEmpty ? "mail.example.com" : "mail.\(domain)"
    }

    var reverseDNSPlaceholder: String {
        "relay.\(domain.isEmpty ? "example.com" : domain)"
    }

    /// The service's default hostname — the placeholder for the corresponding field
    func serviceHostnamePlaceholder(_ id: ServiceID) -> String {
        let base = domain.isEmpty ? "example.com" : domain
        if ServiceID.vpnProtocols.contains(id) { return "vpn.\(base)" }
        let context = ServiceContext(domain: base, sshUser: "", settings: ServiceSettings(),
                                     installedServices: selectedServices)
        return ServiceRegistry.service(id)?.webIngress(context)?.hostname ?? base
    }

    /// Placeholder for the shared VPN domain field
    var vpnHostnamePlaceholder: String {
        "vpn.\(domain.isEmpty ? "example.com" : domain)"
    }

    var publicIPTitle: LocalizedStringKey {
        localOnly ? "Local address of the server"
            : (topology == .singleHost ? "Public IP of the server" : "Public IP of the VPS")
    }

    func serviceDisplayName(_ id: ServiceID) -> String {
        ServiceRegistry.service(id)?.displayName ?? id.rawValue
    }

    func serviceSystemImage(_ id: ServiceID) -> String {
        ServiceRegistry.service(id)?.systemImage ?? "shippingbox"
    }

    struct DNSZonePreview: Identifiable {
        let domain: String
        let records: [DNSRecord]
        let zoneFile: Artifact?
        let csvFile: Artifact?
        var id: String { domain }
    }

    func dnsPreview() -> [DNSZonePreview] {
        guard let input = try? makePreviewInput() else { return [] }
        let context = MailContext(input: input, renderer: StringTemplateRenderer())
        let generator = DNSRecordGenerator()
        let artifacts = (try? generator.generate(in: context)) ?? []
        let all = generator.records(in: context)
        let zones = context.mailDomainNames
        return zones.compactMap { zoneName in
            let owned = all.filter { DNSRecordGenerator.zone(of: $0, among: zones) == zoneName }
            guard !owned.isEmpty else { return nil }
            return DNSZonePreview(
                domain: zoneName,
                records: owned,
                zoneFile: artifacts.first { $0.fileName == DNSRecordGenerator.zoneFileName(domain: zoneName) },
                csvFile: artifacts.first { $0.fileName == DNSRecordGenerator.csvFileName(domain: zoneName) }
            )
        }
    }

    /// The server nodes of the current form
    private func makeServerNodes() throws -> [ServerNode] {
        switch topology {
        case .singleHost:
            return [ServerNode(role: .singleHost,
                               publicAddress: try makeAddress(publicIP),
                               distribution: distribution)]
        case .vpsRelayWithHomeBackend:
            return [
                ServerNode(role: .vpsRelay,
                           publicAddress: try NetworkAddress(parsing: publicIP),
                           vpnAddress: try NetworkAddress(parsing: vpsVPNIP),
                           distribution: distribution),
                ServerNode(role: .homeBackend,
                           vpnAddress: try NetworkAddress(parsing: homeVPNIP),
                           distribution: homeDistribution),
            ]
        }
    }

    private func makeDomain(_ raw: String) throws -> Domain {
        localOnly ? try Domain(localOnly: raw) : try Domain(raw)
    }

    private func makeAddress(_ raw: String) throws -> NetworkAddress {
        scope.publishesAddressRecords ? try NetworkAddress(parsing: raw)
                                      : try NetworkAddress(localOnly: raw)
    }

    private func makePreviewInput() throws -> MailRecipeInput {
        let domainModel = try makeDomain(domain)
        let servers = try makeServerNodes()
        let trimmedPTR = reverseDNSHostname.trimmingCharacters(in: .whitespaces).lowercased()
        return MailRecipeInput(
            domain: domainModel,
            additionalDomains: try additionalDomains
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
                .map { try makeDomain($0) },
            hostname: "mail.\(domainModel.name)",
            reverseDNSHostname: trimmedPTR.isEmpty ? nil : trimmedPTR,
            topology: topology,
            scope: scope,
            servers: servers,
            services: selectedServices,
            serviceSettings: makeServiceSettings(),
            language: ContentLanguageSetting.current
        )
    }

    func generate(persisting: Bool = true) async {
        useDemoAddressesIfLocked()
        if includeDashboardAccess, useExistingUser,
           existingUserPassword.isEmpty {
            errorMessage = UIL10n.string("Enter the existing user's password — the app signs in with it.")
            bundle = nil
            return
        }
        if includeDashboardAccess, useExistingUser, topology == .vpsRelayWithHomeBackend,
           existingUserHomePassword.isEmpty {
            errorMessage = UIL10n.string("Enter the local server's password for that user too.")
            bundle = nil
            return
        }
        if reinstallChangesDomain, !domainChangeConfirmed {
            pendingDomainChange = true
            return
        }
        do {
            let domainModel = try makeDomain(domain)
            if !pinsDeploymentID {
                adoptExistingDeploymentIfAny(domain: domainModel.name)
            }
            let effectiveHostname = "mail.\(domainModel.name)"

            let servers = try makeServerNodes()

            let settings = makeServiceSettings()
            let trimmedPTR = reverseDNSHostname.trimmingCharacters(in: .whitespaces).lowercased()
            let input = MailRecipeInput(
                domain: domainModel,
                additionalDomains: try additionalDomains
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                    .map { try makeDomain($0) },
                hostname: effectiveHostname,
                reverseDNSHostname: trimmedPTR.isEmpty ? nil : trimmedPTR,
                topology: topology,
                scope: scope,
                servers: servers,
                dashboardAccess: try await makeDashboardAccess(settings: settings),
                services: selectedServices,
                serviceSettings: settings,
                language: ContentLanguageSetting.current
            )
            bundle = try MailRecipe(
                keyProvider: KeychainWireGuardKeyProvider(deploymentID: deploymentID)
            ).generate(from: input)
            openPorts = OpenPortsSummary.entryHostPorts(for: input)
            errorMessage = nil
            if pinsDeploymentID {
                InstallSessionRegistry.shared.resetIdleSession(for: deploymentID)
            }
            guard persisting else { return }
            if LicenseStore.isUnlocked { await LicenseStore.shared.noteFirstGeneration() }
            configuratorStore.appendToHistory(snapshot())
            await saveDeploymentIfPossible(domain: domainModel.name, settings: settings)
        } catch let error as ValidationError {
            errorMessage = error.message(ContentLanguageSetting.current)
            bundle = nil
        } catch {
            errorMessage = UIL10n.string("Failed to generate the configuration: %@", String(describing: error))
            bundle = nil
        }
    }

    func makeServiceSettings() -> ServiceSettings {
        var settings = snapshot().serviceSettings
        settings.eraseMailOnDomainChange = erasesMailOnDomainChange
        return settings
    }

    private func adoptExistingDeploymentIfAny(domain: String) {
        let deployments = (try? deploymentStore.load()) ?? []
        if let existing = deployments.first(where: { $0.topology == topology && $0.domain == domain }) {
            deploymentID = existing.id
        } else if deployments.contains(where: { $0.id == deploymentID }) {
            deploymentID = UUID()
        }
    }

    private func makeDashboardAccess(settings: ServiceSettings) async throws -> DashboardAccessInput? {
        guard includeDashboardAccess else { return nil }
        let identity = try await loadIdentity()
        return DashboardAccessInput(
            sshUser: dashboardSSHUser.trimmingCharacters(in: .whitespaces).lowercased(),
            createUser: !useExistingUser,
            appPublicKey: identity.publicKeyOpenSSH,
            mailcowPath: settings.mailcowPath,
            vaultwardenContainer: settings.vaultwardenContainer,
            vaultwardenDataPath: settings.vaultwardenDataPath,
            mailcowBackupDir: settings.mailcowBackupDir,
            vaultwardenBackupDir: settings.vaultwardenBackupDir,
            backupRetention: settings.backupRetention
        )
    }

    private func saveDeploymentIfPossible(domain: String, settings: ServiceSettings) async {
        guard includeDashboardAccess else { return }
        let generated = Deployment(
            id: deploymentID,
            name: domain,
            topology: topology,
            domain: domain,
            additionalDomains: additionalDomains
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty },
            entry: HostEndpoint(host: publicIP.trimmingCharacters(in: .whitespaces),
                                user: dashboardSSHUser.trimmingCharacters(in: .whitespaces).lowercased()),
            homeWGAddress: topology == .vpsRelayWithHomeBackend ? homeVPNIP : nil,
            services: selectedServices,
            serviceSettings: settings,
            usesPasswordAuth: useExistingUser,
            scope: scope
        )
        let deployment = InstalledDeploymentRecord.merged(
            generated: generated,
            onto: (try? deploymentStore.load())?.first { $0.id == deploymentID })
        do {
            if useExistingUser {
                let deploymentID = deploymentID
                let password = existingUserPassword
                let homePassword = existingUserHomePassword
                let isPair = topology == .vpsRelayWithHomeBackend
                try await Task.detached(priority: .userInitiated) {
                    let store = DashboardPasswordStore(deploymentID: deploymentID)
                    try store.save(password, for: .vps)
                    if isPair { try store.save(homePassword, for: .home) }
                }.value
            }
            let onEmulatedMachine = DemoServer.fleetIsDemoOnly((try? deploymentStore.load()) ?? [])
                && DemoServer.isDocumentationHost(deployment.entry.host)
            try deploymentStore.upsert(deployment)
            if onEmulatedMachine {
                DemoServer.remember(installed: deployment.id)
            } else {
                DemoServer.forget(installed: deployment.id)
            }
            savedDeployment = deployment
            let home = homeNetworkAddress.trimmingCharacters(in: .whitespaces)
            if isPairTopology, !home.isEmpty { InstallAddressStore.save(homeAddress: home, deploymentID: deployment.id) }
            configuratorStore.saveDeploymentConfig(snapshot())
        } catch {
            savedDeployment = nil
        }
    }
}
