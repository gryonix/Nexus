import ServerControl
import SwiftUI

struct SecurityAutoRulesView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @AppStorage(SecurityRulesTemplate.storageKey) private var templateJSON = ""

    @State private var draft = HostSecurityAutoRules()
    /// Keeps a returning `.task` from overwriting the edited draft
    @State private var draftLoaded = false
    @State private var newService = ""
    @State private var addingCustomService = false
    #if DEBUG
    /// Screenshot hook — see the probe on the "Countries" row
    @State private var showingCountryPicker = false
    #endif

    var body: some View {
        Form {
            switchSection
            if draft.isOn {
                countriesSection
                thresholdSection
                banSection
                servicesSection
            }
            templateSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Automatic blocking")
        .raisedNavigationTitle()
        .pleaseWait(viewModel.securityAutoRulesBusy)
        .task(id: draft) { await autosave() }
        .onDisappear { saveEdited() }
        .task {
            await viewModel.loadSecurityAutoRules()
            guard !draftLoaded else { return }
            if let rules = viewModel.securityAutoRules {
                draft = rules
                draftLoaded = true
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_AUTORULES"] != nil {
                draft = HostSecurityAutoRules(
                    isOn: true, countries: ["RU", "CN"], countriesAreAllowlist: false,
                    attemptThreshold: 5, attemptWindowMinutes: 10, bansSubnet: true,
                    banSeconds: 24 * 3600,
                    services: [.init(service: "ssh", attemptThreshold: 3)],
                    geoIPAvailable: true)
                draftLoaded = true
            }
            #endif
        }
    }

    // MARK: - The switch

    @ViewBuilder private var switchSection: some View {
        Section {
            Toggle("Block automatically", isOn: $draft.isOn)
        } header: {
            InfoSectionHeader("Automatic blocking", note: "Rules the server itself applies to every attempt, whether this app is running or not — they are written into the protection's own configuration. Without them the engine still blocks what it recognises; these say what else counts as too much.")
        } footer: {
            if let error = viewModel.securityAutoRulesError {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Where from

    @ViewBuilder private var countriesSection: some View {
        Section {
            NavigationLink {
                CountryRegionPickerView(codes: $draft.countries)
            } label: {
                LabeledContent {
                    Text(verbatim: draft.countries.isEmpty ? "—" : "\(draft.countries.count)")
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Countries")
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $showingCountryPicker) {
                CountryRegionPickerView(codes: $draft.countries)
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_COUNTRIES"] != nil
                else { return }
                try? await Task.sleep(for: .milliseconds(1600))
                showingCountryPicker = true
            }
            #endif
            WrappingPicker("These countries are", selection: $draft.countriesAreAllowlist) {
                Text("Blocked").tag(false)
                Text("The only ones allowed").tag(true)
            }
            if !(viewModel.securityAutoRules?.geoIPAvailable ?? true) {
                Label("This server cannot tell where a connection comes from — its protection has no country data installed, so a country rule would never match.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            InfoSectionHeader("Countries", note: "Blocking a country stops every address in it before it has tried anything; allowing only a few is the opposite order and refuses everywhere else, which is worth being sure about — your own phone abroad is somewhere else.")
        }
    }

    // MARK: - How many tries

    @ViewBuilder private var thresholdSection: some View {
        Section {
            Stepper(value: $draft.attemptThreshold, in: 0...100) {
                HStack {
                    Text("Failures before a block")
                    Spacer()
                    Text(verbatim: draft.attemptThreshold == 0
                         ? UIL10n.string("Engine's own") : "\(draft.attemptThreshold)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            InfoSectionHeader("How many tries", note: "Zero leaves the engine's own judgement alone, which is already good at telling a fat finger from a password guesser. Set a number to be stricter than it is.")
        }
    }

    // MARK: - How wide, how long

    @ViewBuilder private var banSection: some View {
        Section {
            LabeledContent {
                Text("Not automatic").font(.caption).foregroundStyle(.secondary)
            } label: {
                Label {
                    Text("Block the whole neighbourhood")
                } icon: {
                    Image(systemName: "square.stack.3d.down.right")
                }
                .foregroundStyle(.secondary)
            }
            Text("CrowdSec writes the automatic decisions itself and can only ban the address that tripped the rule — a range it is asked for comes back covering that one address anyway. A neighbourhood is blocked by hand, from Recent attempts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            WrappingPicker("Blocked for", selection: $draft.banSeconds) {
                Text("Engine's own").tag(TimeInterval(0))
                Text("4 hours").tag(TimeInterval(4 * 3600))
                Text("24 hours").tag(TimeInterval(24 * 3600))
                Text("A week").tag(TimeInterval(7 * 24 * 3600))
                Text("Forever").tag(SecurityBanDuration.untilLifted)
            }
        } header: {
            InfoSectionHeader("How wide and how long", note: "A scan arrives from a hoster's range rather than from one address, so blocking the address it used this minute is work the next minute undoes — the neighbourhood is the /24 around it. Blocking a whole range also catches machines that have done nothing, which is the price.")
        }
    }

    // MARK: - Per service

    @ViewBuilder private var servicesSection: some View {
        Section {
            ForEach($draft.services) { $rule in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: rule.service).font(.callout)
                    Stepper(value: $rule.attemptThreshold, in: 0...100) {
                        HStack {
                            Text("Failures")
                            Spacer()
                            Text(verbatim: rule.attemptThreshold == 0
                                 ? UIL10n.string("Engine's own") : "\(rule.attemptThreshold)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
            .onDelete { offsets in draft.services.remove(atOffsets: offsets) }

            if addingCustomService {
                HStack {
                    TextField("Service", text: $newService,
                              prompt: Text(verbatim: "smtp").foregroundStyle(.secondary))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Button {
                        addService(newService)
                        newService = ""
                        addingCustomService = false
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(newService.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button {
                        newService = ""
                        addingCustomService = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Menu {
                    Button("SSH") { addService("ssh") }
                        .disabled(draft.services.contains { $0.service == "ssh" })
                    Button("Website (HTTP)") { addService("http") }
                        .disabled(draft.services.contains { $0.service == "http" })
                    Divider()
                    Button("Other…") { addingCustomService = true }
                } label: {
                    Label("Add a service", systemImage: "plus.circle")
                }
                .rowActionButtonStyle()
            }
        } header: {
            InfoSectionHeader("Per service", note: "A wrong password on SSH is a break-in attempt; a wrong password on a web form is Tuesday. Name the service as the protection names it — ssh, http, smtp — and it is matched against what the engine actually fired.")
        }
    }

    private func addService(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, !draft.services.contains(where: { $0.service == name }) else { return }
        draft.services.append(.init(service: name))
    }

    // MARK: - The template

    @ViewBuilder private var templateSection: some View {
        Section {
            Button {
                SecurityRulesTemplate.save(draft)
            } label: {
                Label("Save these as the fleet default", systemImage: "square.and.arrow.down")
            }
            .rowActionButtonStyle()
            if let template = SecurityRulesTemplate.load(from: templateJSON) {
                Button {
                    draft = template
                } label: {
                    Label("Use the fleet default", systemImage: "arrow.down.doc")
                }
                .rowActionButtonStyle()
            }
        } header: {
            InfoSectionHeader("Fleet default", note: "One set of rules kept on this device and applied to any server you choose — a mail server and a game server want different answers, so it is a starting point rather than a policy. Each server keeps what it was actually given.")
        } footer: {
            if let template = SecurityRulesTemplate.load(from: templateJSON),
               template != draft, viewModel.securityAutoRules != nil {
                Text("This server's rules differ from the fleet default.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sending an edit

    /// Sends the edited rules a moment after the last change
    private func autosave() async {
        guard hasEdit else { return }
        try? await Task.sleep(for: .milliseconds(1200))
        guard !Task.isCancelled, hasEdit else { return }
        let edited = draft
        await viewModel.saveSecurityAutoRules(edited)
        guard !Task.isCancelled, viewModel.securityAutoRulesError == nil else { return }
        // Show the rules the host recorded, not the draft
        if let saved = viewModel.securityAutoRules, saved != edited { draft = saved }
    }

    /// Leaving before that pause elapsed still sends the edit
    private func saveEdited() {
        guard hasEdit else { return }
        let edited = draft
        Task { await viewModel.saveSecurityAutoRules(edited) }
    }

    private var hasEdit: Bool {
        draftLoaded && viewModel.securityAutoRules != nil && draft != viewModel.securityAutoRules
    }
}

enum SecurityRulesTemplate {
    static let storageKey = "security.autoRulesTemplate"

    static func save(_ rules: HostSecurityAutoRules, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: storageKey)
    }

    static func load(from stored: String) -> HostSecurityAutoRules? {
        guard !stored.isEmpty, let data = stored.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HostSecurityAutoRules.self, from: data)
    }
}
