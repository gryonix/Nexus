import SwiftUI
import gryonixNexusCore

enum DNSProviderKind: String, CaseIterable, Identifiable, Sendable {
    case cloudflare
    case digitalOcean
    case hetzner
    case porkbun
    case ovh
    case route53
    case googleCloud
    case godaddy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .digitalOcean: return "DigitalOcean"
        case .hetzner: return "Hetzner"
        case .porkbun: return "Porkbun"
        case .ovh: return "OVHcloud"
        case .route53: return "Amazon Route 53"
        case .googleCloud: return "Google Cloud DNS"
        case .godaddy: return "GoDaddy"
        }
    }

    var tokenFieldLabel: LocalizedStringKey {
        switch self {
        case .cloudflare, .digitalOcean, .hetzner, .porkbun, .ovh, .route53, .googleCloud, .godaddy:
            return "DNS provider API token"
        }
    }

    var publishButtonLabel: LocalizedStringKey {
        switch self {
        case .cloudflare, .digitalOcean, .hetzner, .porkbun, .ovh, .route53, .googleCloud, .godaddy:
            return "Publish records"
        }
    }

    var setupHint: LocalizedStringKey {
        switch self {
        case .cloudflare:
            return "Create the token at Cloudflare with the Zone → DNS → Edit permission for your zone. It is kept in the Keychain on this device and used only to write the records above. Records are created as “DNS only”, never proxied."
        case .digitalOcean:
            return "Create the token under API → Tokens/Keys with read and write scope. It is kept in the Keychain on this device and used only to write the records above."
        case .hetzner:
            return "Create the token in the DNS console under API Tokens. It is kept in the Keychain on this device and used only to write the records above."
        case .porkbun:
            return "Create an API key under Account → API Access, and enable API access for this domain in its Domain Management page. Porkbun needs both the API key and the secret key — paste them here together, separated by a colon: apikey:secretapikey. Kept in the Keychain on this device and used only to write the records above."
        case .ovh:
            return "Create a token at api.ovh.com/createToken with the rights GET/POST/PUT on /domain/zone/*. OVH gives you three keys — application key, application secret and consumer key — paste all three here, separated by colons: applicationKey:applicationSecret:consumerKey. Uses the EU endpoint (eu.api.ovh.com). Kept in the Keychain on this device and used only to write the records above."
        case .route53:
            return "Create an IAM user with the AmazonRoute53FullAccess policy (or a custom policy scoped to your hosted zone) and an access key for it. Paste the access key ID and the secret access key here together, separated by a colon: accessKeyID:secretAccessKey. Kept in the Keychain on this device and used only to write the records above."
        case .googleCloud:
            return "Create a service account with the DNS Administrator role, then create a JSON key for it and paste the WHOLE downloaded file here — client email, private key and project id all travel together in that one file. Kept in the Keychain on this device and used only to write the records above."
        case .godaddy:
            return "Create a Personal Access Token from the GoDaddy Developer dashboard. It is kept in the Keychain on this device and used only to write the records above."
        }
    }

    func makeProvider(token: String) -> any DNSPublishingProvider {
        switch self {
        case .cloudflare: return CloudflareDNSProvider(token: token)
        case .digitalOcean: return DigitalOceanDNSProvider(token: token)
        case .hetzner: return HetznerDNSProvider(token: token)
        case .porkbun: return PorkbunDNSProvider(token: token)
        case .ovh: return OVHDNSProvider(token: token)
        case .route53: return Route53DNSProvider(token: token)
        case .googleCloud: return GoogleCloudDNSProvider(token: token)
        case .godaddy: return GoDaddyDNSProvider(token: token)
        }
    }
}

struct DNSProviderPublishSection: View {
    let zones: [ServiceConfigViewModel.DNSZonePreview]
    var onPublishSucceeded: (() -> Void)?

    @StateObject private var model = DNSProviderPublishModel()
    @ObservedObject private var credentials = DNSCredentials.shared

    var body: some View {
        Section {
            if DNSProviderKind.allCases.count > 1 {
                WrappingPicker("Provider", selection: $model.providerKind) {
                    ForEach(DNSProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: model.providerKind) { _, _ in
                    Task { await model.loadTokenForCurrentProvider() }
                }
            }

            if model.saved.count > 1 {
                WrappingPicker("Token", selection: $model.credentialID) {
                    ForEach(model.saved) { credential in
                        Text(verbatim: credential.name).tag(credential.id as String?)
                    }
                }
                .onChange(of: model.credentialID) { _, newID in
                    Task { await model.loadToken(for: newID) }
                }
            }

            SecureField(model.providerKind.tokenFieldLabel, text: $model.token)
                .textContentType(.password)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            Button {
                Task {
                    await model.publish(zones: zones)
                    if !model.failed { onPublishSucceeded?() }
                }
            } label: {
                HStack {
                    Text(model.providerKind.publishButtonLabel)
                    if model.isWorking {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .rowActionButtonStyle()
            .disabled(model.token.isEmpty || model.isWorking || zones.isEmpty)

            ForEach(model.lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(model.failed ? .red : .secondary)
            }
        } header: {
            Text("Publish automatically")
        } footer: {
            Text(model.providerKind.setupHint)
        }
        .task { await model.loadStoredToken() }
    }
}

@MainActor
final class DNSProviderPublishModel: ObservableObject {
    @Published var providerKind: DNSProviderKind =
        DNSCredentials.shared.selected?.kind ?? .cloudflare
    @Published var token = ""
    @Published var credentialID: String? = DNSCredentials.shared.selectedID
    /// Every saved credential for the provider currently picked
    @Published private(set) var saved: [DNSCredential] = []
    @Published private(set) var lines: [String] = []
    @Published private(set) var isWorking = false
    @Published private(set) var failed = false

    func loadStoredToken() async {
        guard token.isEmpty else { return }
        await loadTokenForCurrentProvider()
    }

    func loadToken(for id: String?) async {
        credentialID = id
        guard let credential = saved.first(where: { $0.id == id }) else {
            token = ""
            return
        }
        token = await DNSCredentialTokenStore.load(credential) ?? ""
    }

    func loadTokenForCurrentProvider() async {
        let credentials = DNSCredentials.shared
        await credentials.adoptStoredTokensIfNeeded()
        saved = credentials.all.filter { $0.kind == providerKind }
        let chosen = saved.first { $0.id == credentialID } ?? saved.first
        await loadToken(for: chosen?.id)
    }

    /// Verifies the token, then applies every zone
    func publish(zones: [ServiceConfigViewModel.DNSZonePreview]) async {
        isWorking = true
        failed = false
        lines = []
        defer { isWorking = false }

        let provider = providerKind.makeProvider(token: token)
        do {
            try await provider.verifyToken()
            try await save(token)
        } catch {
            failed = true
            lines = [message(for: error)]
            return
        }

        for zone in zones {
            do {
                let outcomes = try await provider.publishReportingOutcomes(zone.records,
                                                                           zone: zone.domain)
                lines.append(contentsOf: summary(of: outcomes, zone: zone.domain))
            } catch {
                failed = true
                lines.append("\(zone.domain): \(message(for: error))")
            }
        }
    }

    private func save(_ token: String) async throws {
        let credentials = DNSCredentials.shared
        let credential = saved.first { $0.id == credentialID }
            ?? credentials.add(named: providerKind.displayName, kind: providerKind)
        try await DNSCredentialTokenStore.save(token, for: credential)
        saved = credentials.all.filter { $0.kind == providerKind }
        credentialID = credential.id
    }

    private func summary(of outcomes: [DNSPublishOutcome],
                         zone: String) -> [String] {
        var created = 0, updated = 0, unchanged = 0
        var problems: [String] = []
        for outcome in outcomes {
            switch outcome.result {
            case .created: created += 1
            case .updated: updated += 1
            case .unchanged: unchanged += 1
            case .failed(let reason):
                failed = true
                problems.append("\(outcome.record.name): \(reason)")
            }
        }
        let head = UIL10n.string("%@: %lld added, %lld updated, %lld already correct.",
                                 zone, created, updated, unchanged)
        return [head] + problems
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
