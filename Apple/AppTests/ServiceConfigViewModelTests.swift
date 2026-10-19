import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class AutheliaProtectionTests: XCTestCase {
    private func model() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        return model
    }

    func testOnlyServicesWithASiteCanBeProtected() {
        let model = model()
        model.extraServices = [.authelia, .adguardHome, .vaultwarden, .shadowsocks]
        model.vpnEnabled = true
        model.vpnProtocols = [.shadowsocks]

        let candidates = Set(model.autheliaCandidates)
        XCTAssertTrue(candidates.contains(.adguardHome))
        XCTAssertTrue(candidates.contains(.vaultwarden))
        XCTAssertFalse(candidates.contains(.authelia),
                       "the portal cannot stand in front of itself")
        XCTAssertFalse(candidates.contains(.shadowsocks),
                       "a VPN protocol has no web face, so there is no site to guard")
    }

    func testTheDefaultSetNeverIncludesAServiceWithAPhoneApp() {
        let model = model()
        for id in model.autheliaProtectedServices {
            XCTAssertFalse(AutheliaService.breaksAppClients.contains(id),
                           "\(id.rawValue) is protected by default and its app would stop connecting")
        }
        XCTAssertEqual(model.autheliaProtectedServices, AutheliaService.defaultProtected)
    }

    func testTheProtectionBindingAddsAndRemoves() {
        let model = model()
        let binding = model.autheliaProtectionBinding(.vaultwarden)
        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertTrue(model.autheliaProtectedServices.contains(.vaultwarden))
        binding.wrappedValue = false
        XCTAssertFalse(model.autheliaProtectedServices.contains(.vaultwarden))
    }

    func testTheChosenSetReachesTheGeneratedSettings() {
        let model = model()
        model.extraServices = [.authelia, .adguardHome, .homepage]
        model.autheliaProtectedServices = [.homepage]
        XCTAssertEqual(model.makeServiceSettings().autheliaProtectedServices, [.homepage])
    }
}

@MainActor
final class NewShelvesAreOfferedTests: XCTestCase {
    func testTheNewShelvesAreOfferedOnAPublicDeployment() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        let shelves = Set(model.availableCategories.map(\.id))
        XCTAssertTrue(shelves.contains(ServiceCategory.dashboard.id))
        XCTAssertTrue(shelves.contains(ServiceCategory.singleSignOn.id))
        XCTAssertTrue(shelves.contains(ServiceCategory.network.id))
    }

    func testTheNewShelvesSurviveLocalOnly() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .localOnly)
        let shelves = Set(model.availableCategories.map(\.id))
        XCTAssertTrue(shelves.contains(ServiceCategory.dashboard.id))
        XCTAssertTrue(shelves.contains(ServiceCategory.singleSignOn.id))
    }

    func testTheDNSShelfOffersBothEnginesAndTheyExclude() {
        let members = ServiceRegistry.services(in: .network).map(\.id)
        XCTAssertEqual(members, [.adguardHome, .pihole])
        XCTAssertEqual(ServiceRegistry.service(.pihole)?.conflicts, [.adguardHome])
        XCTAssertEqual(ServiceRegistry.service(.adguardHome)?.conflicts, [.pihole])
    }
}

@MainActor
final class VPNShelfSelectionTests: XCTestCase {
    private func model() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        return model
    }

    func testUntickingTheLastProtocolClearsTheShelf() {
        let model = model()
        model.categoryBinding(.vpn).wrappedValue = true
        XCTAssertEqual(model.selection(in: .vpn), [.wireguardVPN])

        model.vpnProtocolBinding(.wireguardVPN).wrappedValue = false

        XCTAssertTrue(model.selection(in: .vpn).isEmpty)
        XCTAssertFalse(model.vpnEnabled,
                       "the flag has to follow the set, or the form keeps drawing rows the switch says are gone")
        XCTAssertFalse(model.categoryBinding(.vpn).wrappedValue)
    }

    func testUntickingOneOfSeveralKeepsTheShelfOn() {
        let model = model()
        model.vpnProtocolBinding(.wireguardVPN).wrappedValue = true
        model.vpnProtocolBinding(.openVPN).wrappedValue = true
        XCTAssertEqual(model.selection(in: .vpn), [.wireguardVPN, .openVPN])

        model.vpnProtocolBinding(.openVPN).wrappedValue = false

        XCTAssertEqual(model.selection(in: .vpn), [.wireguardVPN])
        XCTAssertTrue(model.vpnEnabled)
    }

    func testTickingAProtocolTurnsTheShelfOn() {
        let model = model()
        model.vpnProtocolBinding(.shadowsocks).wrappedValue = true

        XCTAssertTrue(model.vpnEnabled)
        XCTAssertTrue(model.selectedServices.contains(.shadowsocks))
        XCTAssertTrue(model.selectedServices.contains(.vpnPanel),
                      "any protocol implies the panel that hands out its profiles")
    }

    func testRestoringASplitDraftNormalisesIt() {
        var draft = ConfiguratorDraft(topology: .singleHost)
        draft.vpnEnabled = true
        draft.vpnProtocols = []

        let model = model()
        model.apply(draft)

        XCTAssertFalse(model.vpnEnabled)
        XCTAssertTrue(model.selection(in: .vpn).isEmpty)
    }
}

/// The per-service domain fields
@MainActor
final class ServiceHostnameFieldTests: XCTestCase {
    private func model() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        return model
    }

    /// Every nameable service reaches generation
    func testEveryNameableServiceReachesGeneration() {
        let model = model()
        for id in ServiceSettings.hostnameSettings.keys {
            model.serviceHostnames[id] = "\(id.rawValue).example.org"
        }
        let settings = model.makeServiceSettings()
        for (id, keyPath) in ServiceSettings.hostnameSettings {
            XCTAssertEqual(settings[keyPath: keyPath], "\(id.rawValue).example.org",
                           "\(id.rawValue) was typed into the form and did not arrive")
        }
    }

    func testTwoEnginesOnOneShelfGetTheirOwnNames() {
        let model = model()
        model.extraServices = [.nextcloud, .seafile]
        let settings = model.makeServiceSettings()
        let context = ServiceContext(domain: "example.com", sshUser: "", settings: settings,
                                     installedServices: [.nextcloud, .seafile])
        let names = [ServiceID.nextcloud, .seafile].compactMap {
            ServiceRegistry.service($0)?.webIngress(context)?.hostname
        }
        XCTAssertEqual(names, ["nextcloud.example.com", "seafile.example.com"])
    }

    func testThePlaceholderFollowsWhatElseIsSelected() {
        let model = model()
        model.extraServices = [.seafile]
        XCTAssertEqual(model.serviceHostnamePlaceholder(.seafile), "files.example.com")
        model.extraServices = [.seafile, .nextcloud]
        XCTAssertEqual(model.serviceHostnamePlaceholder(.seafile), "seafile.example.com")
        XCTAssertEqual(model.serviceHostnamePlaceholder(.nextcloud), "nextcloud.example.com")
    }

    func testABlankFieldKeepsTheDefaultSubdomain() {
        let model = model()
        model.serviceHostnames[.seafile] = ""
        let settings = model.makeServiceSettings()
        let context = ServiceContext(domain: "example.com", sshUser: "", settings: settings)
        XCTAssertEqual(ServiceRegistry.service(.seafile)?.webIngress(context)?.hostname,
                       "files.example.com")
    }

    func testTheHostnameBindingReadsAndWrites() {
        let model = model()
        let binding = model.hostnameBinding(.photoprism)
        XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "pics.example.org"
        XCTAssertEqual(model.serviceHostnames[.photoprism], "pics.example.org")
    }

    func testNamesSurviveTheDraftRoundTrip() {
        let saved = model()
        saved.serviceHostnames = [.psono: "keys.example.org", .headscale: "mesh.example.org"]
        let restored = model()
        restored.apply(saved.snapshot())
        XCTAssertEqual(restored.serviceHostnames[.psono], "keys.example.org")
        XCTAssertEqual(restored.serviceHostnames[.headscale], "mesh.example.org")
    }

    func testALegacyDraftStillCarriesItsFiveNames() {
        var draft = ConfiguratorDraft(topology: .singleHost)
        draft.vaultwardenHostname = "vault.example.org"
        draft.gitlabHostname = "git.example.org"

        let model = model()
        model.apply(draft)

        XCTAssertEqual(model.serviceHostnames[.vaultwarden], "vault.example.org")
        XCTAssertEqual(model.serviceHostnames[.gitlab], "git.example.org")
    }

    func testADraftWrittenNowStillFillsTheLegacyFields() {
        let model = model()
        model.serviceHostnames = [.vaultwarden: "vault.example.org"]
        let draft = model.snapshot()
        XCTAssertEqual(draft.vaultwardenHostname, "vault.example.org")
        XCTAssertEqual(draft.serviceHostnames?[ServiceID.vaultwarden.rawValue],
                       "vault.example.org")
    }

    /// Export and the live form must name the same hosts
    func testExportNamesTheSameHostsAsTheForm() throws {
        let model = model()
        model.publicIP = "203.0.113.10"
        model.extraServices = [.nextcloud, .seafile, .photoprism]
        model.serviceHostnames = [.seafile: "files.example.org",
                                  .photoprism: "pics.example.org"]
        let expected: [ServiceID: String] = [.seafile: "files.example.org",
                                             .photoprism: "pics.example.org"]
        let fromForm = model.makeServiceSettings()
        let fromExport = try model.snapshot().makeMailRecipeInput().serviceSettings
        XCTAssertEqual(fromForm.namedHostnames, expected)
        XCTAssertEqual(fromExport.namedHostnames, expected)
    }
}

/// The form's settings and the exported configuration's settings
@MainActor
final class SettingsAssemblyTests: XCTestCase {
    private func answeredModel() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        model.publicIP = "203.0.113.10"
        model.extraServices = [.pihole, .authelia, .seafile, .forgejo, .gitlab]
        model.serviceHostnames = [.seafile: "files.example.org",
                                  .pihole: "filter.example.org"]
        model.piholeServesNetwork = true
        model.autheliaProtectedServices = [.pihole]
        model.vaultwardenAllowSignups = false
        model.adminUsername = "owner"
        model.forgejoSSHPort = "2299"
        model.gitlabSSHPort = "2298"
        model.vpnHostname = "tunnel.example.org"
        model.xrayRealitySNI = "www.example.net"
        return model
    }

    /// Every answer survives the trip, field for field
    func testTheExportedSettingsAreTheFormsSettings() {
        let model = answeredModel()
        var fromDraft = model.snapshot().serviceSettings
        fromDraft.eraseMailOnDomainChange = model.makeServiceSettings().eraseMailOnDomainChange
        XCTAssertEqual(model.makeServiceSettings(), fromDraft)
    }

    func testPiholeReachesTheExportedPorts() throws {
        let model = answeredModel()
        let input = try model.snapshot().makeMailRecipeInput()
        let context = ServiceContext(domain: "example.com", sshUser: "",
                                     settings: input.serviceSettings)
        let ports = try XCTUnwrap(ServiceRegistry.service(.pihole)).firewallPorts(context)
        XCTAssertEqual(ports.map { "\($0.port)/\($0.proto.rawValue)" }, ["53/tcp", "53/udp"],
                       "the export dropped the answer that publishes Pi-hole's DNS port")
    }

    func testAnExplicitlyEmptyProtectionSetSurvivesTheExport() throws {
        let model = answeredModel()
        model.autheliaProtectedServices = []
        let input = try model.snapshot().makeMailRecipeInput()
        XCTAssertEqual(input.serviceSettings.autheliaProtectedServices, [])
    }
}

#if DEBUG
import AgentControl

@MainActor
final class LiveInstallRequestDump: XCTestCase {
    func testDumpInstallRequest() throws {
        let paramsPath = "/tmp/gryonixnexus-dump-params.json"
        guard let raw = FileManager.default.contents(atPath: paramsPath),
              let env = try JSONSerialization.jsonObject(with: raw) as? [String: String],
              let serviceRaw = env["service"] else {
            throw XCTSkip("write \(paramsPath) to dump a request")
        }
        var seed = ConfiguratorDraft(topology: .singleHost)
        seed.scope = .publicInternet
        seed.domain = env["domain"] ?? "example.com"
        seed.additionalDomains = (env["aliases"] ?? "")
            .split(separator: ",").map(String.init)
        seed.adminUsername = env["admin"] ?? "admin"
        let model = ServiceConfigViewModel(topology: .singleHost,
                                           initialScope: .publicInternet,
                                           restoringConfig: seed)
        for pair in (env["hostnames"] ?? "").split(separator: ",") {
            let halves = pair.split(separator: "=", maxSplits: 1)
            guard halves.count == 2 else { continue }
            model.serviceHostnames[ServiceID(rawValue: String(halves[0]))] = String(halves[1])
        }
        for raw in (env["installed"] ?? "").split(separator: ",") {
            model.extraServices.insert(ServiceID(rawValue: String(raw)))
        }
        model.autheliaProtectedServices = Set((env["protected"] ?? "")
            .split(separator: ",").map { ServiceID(rawValue: String($0)) })

        let body: [String: Any] = [
            "serviceId": serviceRaw,
            "domain": env["domain"] ?? model.domain,
            "additionalDomains": model.additionalDomains,
            "localOnly": false,
            "adminUsername": model.adminUsername,
            "language": "en",
            "settings": AgentInstallSettings.map(from: model.makeServiceSettings()),
        ]
        let json = try JSONSerialization.data(withJSONObject: body,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        print("GRYONIXNEXUS_INSTALL_REQUEST_BEGIN")
        print(String(decoding: json, as: UTF8.self))
        print("GRYONIXNEXUS_INSTALL_REQUEST_END")
    }
}
#endif

/// The two "all at once" switches
@MainActor
final class SelectEverythingTests: XCTestCase {
    private func model() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        return model
    }

    func testAllProtocolsTurnsOnEveryOne() {
        let model = model()
        model.setAllVPNProtocols(true)
        XCTAssertEqual(model.selection(in: .vpn), Set(ServiceConfigViewModel.allVPNProtocols))
        XCTAssertTrue(model.allVPNProtocolsSelected)
        XCTAssertTrue(model.vpnEnabled, "the shelf's own flag has to follow, like any other write")
    }

    func testTurningAllProtocolsOffLeavesTheDefaultOne() {
        let model = model()
        model.setAllVPNProtocols(true)
        model.setAllVPNProtocols(false)
        XCTAssertEqual(model.selection(in: .vpn), [.wireguardVPN])
        XCTAssertTrue(model.vpnEnabled)
    }

    func testUntickingOneProtocolClearsTheAllSwitch() {
        let model = model()
        model.setAllVPNProtocols(true)
        model.vpnProtocolBinding(.openVPN).wrappedValue = false
        XCTAssertFalse(model.allVPNProtocolsSelected)
    }

    func testAllSitesBehindTheLoginCoversEveryCandidate() {
        let model = model()
        model.extraServices = [.authelia, .adguardHome, .vaultwarden, .nextcloud]
        model.setAllAutheliaProtection(true)
        XCTAssertEqual(model.autheliaProtectedServices, Set(model.autheliaCandidates))
        XCTAssertTrue(model.allAutheliaCandidatesProtected)
        XCTAssertFalse(model.autheliaProtectedServices.contains(.authelia),
                       "the portal cannot stand in front of itself, all-switch or not")
    }

    func testTurningTheLoginSwitchOffReturnsToTheSafeSet() {
        let model = model()
        model.extraServices = [.authelia, .adguardHome, .vaultwarden]
        model.setAllAutheliaProtection(true)
        model.setAllAutheliaProtection(false)
        XCTAssertEqual(model.autheliaProtectedServices, AutheliaService.defaultProtected)
        XCTAssertFalse(model.autheliaProtectedServices.contains(.vaultwarden),
                       "its phone app cannot pass a browser login — that is why the safe set exists")
    }

    func testTheCodeShelfDefaultsToForgejo() {
        let model = model()
        model.categoryBinding(.code).wrappedValue = true
        XCTAssertEqual(model.selection(in: .code), [.forgejo])
    }
}

@MainActor
final class MetricsPreferencesTests: XCTestCase {
    private func fresh() -> MetricsPreferences {
        let defaults = UserDefaults(suiteName: "metrics.prefs.\(UUID().uuidString)")!
        return MetricsPreferences(defaults: defaults)
    }

    func testTheDefaultsAreTheListThatShipped() {
        let prefs = fresh()
        XCTAssertEqual(prefs.offeredRanges,
                       [.tenMinutes, .hour, .threeHours, .tenHours, .day, .week, .month, .year])
        XCTAssertEqual(prefs.offeredMetrics, HistoryMetric.allCases)
    }

    func testTheNewPeriodsAreAvailableButNotDefault() {
        let prefs = fresh()
        for range in [HistoryRange.thirtyMinutes, .fiveHours, .twelveDays, .sixMonths] {
            XCTAssertTrue(HistoryRange.allCases.contains(range))
            XCTAssertFalse(prefs.offeredRanges.contains(range))
        }
    }

    func testTheOfferedListStaysInCatalogueOrder() {
        let prefs = fresh()
        prefs.setRange(.sixMonths, offered: true)
        prefs.setRange(.thirtyMinutes, offered: true)
        let spans = prefs.offeredRanges.map(\.span)
        XCTAssertEqual(spans, spans.sorted(),
                       "an hour must never sit to the right of a day")
    }

    func testTheLastPeriodCannotBeUnticked() {
        let prefs = fresh()
        for range in HistoryRange.allCases { prefs.setRange(range, offered: false) }
        XCTAssertEqual(prefs.offeredRanges.count, 1)
        let survivor = prefs.offeredRanges[0]
        prefs.setRange(survivor, offered: false)
        XCTAssertEqual(prefs.offeredRanges, [survivor])
    }

    func testTheLastMetricCannotBeUnticked() {
        let prefs = fresh()
        for metric in HistoryMetric.allCases { prefs.setMetric(metric, offered: false) }
        XCTAssertEqual(prefs.offeredMetrics.count, 1)
    }

    func testAnUnofferedPeriodResolvesToAnOfferedOne() {
        let prefs = fresh()
        prefs.setRange(.week, offered: false)
        XCTAssertNotEqual(prefs.resolved(.week), .week)
        XCTAssertTrue(prefs.offeredRanges.contains(prefs.resolved(.week)))
    }

    func testTheChoiceIsRemembered() {
        let suite = "metrics.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = MetricsPreferences(defaults: defaults)
        first.setRange(.sixMonths, offered: true)
        first.setRange(.year, offered: false)

        let second = MetricsPreferences(defaults: defaults)
        XCTAssertTrue(second.offeredRanges.contains(.sixMonths))
        XCTAssertFalse(second.offeredRanges.contains(.year))
    }

    func testEveryPeriodMapsToACollectorBucket() {
        let known: Set<MetricsHistoryBucket> = Set(MetricsHistoryBucket.allCases)
        for range in HistoryRange.allCases {
            XCTAssertTrue(known.contains(range.bucket), "\(range.rawValue) names no bucket")
        }
    }
}

/// Where VPN client configurations come from
@MainActor
final class VPNClientAccessTests: XCTestCase {
    private func context(_ access: VPNClientAccess) -> ServiceContext {
        var settings = ServiceSettings()
        settings.vpnClientAccess = access
        return ServiceContext(domain: "example.com", sshUser: "", settings: settings)
    }

    func testTheDefaultPublishesThePanelLikeBefore() {
        XCTAssertEqual(ServiceSettings().vpnClientAccess, .both)
        let panel = VPNPanelService()
        XCTAssertEqual(panel.webIngress(context(.both))?.hostname, "vpn.example.com")
        XCTAssertEqual(panel.dnsHostnames(context(.both)), ["vpn.example.com"])
    }

    /// App-only drops the site AND the DNS name together
    func testAppOnlyDropsTheSiteAndItsNameTogether() {
        let panel = VPNPanelService()
        XCTAssertNil(panel.webIngress(context(.app)))
        XCTAssertTrue(panel.dnsHostnames(context(.app)).isEmpty)
    }

    /// Panel-only still publishes — that is the whole point of it
    func testPanelOnlyKeepsTheSite() {
        let panel = VPNPanelService()
        XCTAssertEqual(panel.webIngress(context(.panel))?.hostname, "vpn.example.com")
    }

    /// And the two halves of the answer never disagree
    func testTheTwoQuestionsAgreeWithTheCases() {
        XCTAssertFalse(VPNClientAccess.app.publishesPanelSite)
        XCTAssertTrue(VPNClientAccess.app.allowsAppManagement)
        XCTAssertTrue(VPNClientAccess.panel.publishesPanelSite)
        XCTAssertFalse(VPNClientAccess.panel.allowsAppManagement)
        XCTAssertTrue(VPNClientAccess.both.publishesPanelSite)
        XCTAssertTrue(VPNClientAccess.both.allowsAppManagement)
    }

    func testTheChoiceSurvivesTheFormAndTheDraft() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        model.vpnClientAccess = .app
        XCTAssertEqual(model.makeServiceSettings().vpnClientAccess, .app)

        let restored = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        restored.apply(model.snapshot())
        XCTAssertEqual(restored.vpnClientAccess, .app)
    }

    func testAnOlderDraftMeansBoth() {
        var draft = ConfiguratorDraft(topology: .singleHost)
        draft.vpnClientAccess = nil
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.apply(draft)
        XCTAssertEqual(model.vpnClientAccess, .both)
    }
}
