import XCTest

@testable import gryonixNexus

@MainActor
final class DNSCredentialsTests: XCTestCase {
    private func store(_ name: String) -> (DNSCredentials, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (DNSCredentials(defaults: defaults), defaults)
    }

    // MARK: - Nothing moves in the Keychain

    /// The single-account build wrote `cloudflare-api-token` with no id in it
    func testTheOriginalCloudflareAccountKeepsItsOwnItemNames() {
        XCTAssertEqual(DNSCredentials.tokenItem(id: DNSCredentials.cloudflareFirstID,
                                                kind: .cloudflare),
                       "cloudflare-api-token")
        XCTAssertEqual(DNSCredentials.tunnelItem(id: DNSCredentials.cloudflareFirstID),
                       "cloudflare-tunnel-api-token")
    }

    func testALaterCloudflareAccountKeepsItsSuffixedItemNames() {
        XCTAssertEqual(DNSCredentials.tokenItem(id: "ABC", kind: .cloudflare),
                       "cloudflare-api-token.ABC")
        XCTAssertEqual(DNSCredentials.tunnelItem(id: "ABC"), "cloudflare-tunnel-api-token.ABC")
    }

    func testACredentialAdoptedFromThePerKindStoreReadsThatStoresItem() {
        for kind in DNSProviderKind.allCases where kind != .cloudflare {
            XCTAssertEqual(
                DNSCredentials.tokenItem(id: DNSCredentials.adoptedID(for: kind), kind: kind),
                "dns-provider-token.\(kind.rawValue)",
                "\(kind.displayName) would lose the token this device already has")
        }
    }

    func testASecondTokenForAProviderGetsAnItemOfItsOwn() {
        let first = DNSCredentials.tokenItem(id: DNSCredentials.adoptedID(for: .hetzner),
                                             kind: .hetzner)
        let second = DNSCredentials.tokenItem(id: "9E2F", kind: .hetzner)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second, "dns-credential-token.9E2F")
    }

    // MARK: - The list

    func testAFreshDeviceListsNothingAtAll() {
        let (credentials, _) = store("dns.fresh")
        XCTAssertTrue(credentials.all.isEmpty)
        XCTAssertNil(credentials.selectedID)
        XCTAssertNil(credentials.selected)
    }

    func testAnAddedCredentialCarriesItsNameAndProviderAndIsChosen() {
        let (credentials, _) = store("dns.add")
        let added = credentials.add(named: "work", kind: .hetzner)
        XCTAssertEqual(credentials.all.map(\.id), [added.id])
        XCTAssertEqual(credentials.all.first?.name, "work")
        XCTAssertEqual(credentials.all.first?.kind, .hetzner)
        XCTAssertEqual(credentials.selectedID, added.id,
                       "the first credential a device has is the one it publishes with")
    }

    func testAnUnnamedCredentialFallsBackToTheProvidersName() {
        let (credentials, _) = store("dns.unnamed")
        let added = credentials.add(named: "   ", kind: .porkbun)
        XCTAssertEqual(credentials.credential(added.id).name,
                       DNSProviderKind.porkbun.displayName)
    }

    func testDeletingTheChosenCredentialMovesTheChoice() async {
        let (credentials, _) = store("dns.delete")
        let first = credentials.add(named: "one", kind: .cloudflare)
        let second = credentials.add(named: "two", kind: .digitalOcean)
        credentials.selectedID = second.id

        await credentials.remove(second.id)
        XCTAssertEqual(credentials.all.map(\.id), [first.id])
        XCTAssertEqual(credentials.selectedID, first.id)
    }

    // MARK: - What an upgrade finds

    func testAStoredCloudflareAccountListComesAcrossWholly() async {
        let (credentials, defaults) = store("dns.migrate.cloudflare")
        defaults.set([DNSCredentials.cloudflareFirstID, "SECOND"],
                     forKey: DNSCredentials.Legacy.cloudflareIDsKey)
        defaults.set("work", forKey: DNSCredentials.Legacy.cloudflareNamePrefix + "SECOND")
        defaults.set("SECOND", forKey: DNSCredentials.Legacy.cloudflareSelectedKey)

        await credentials.adoptStoredTokensIfNeeded()

        XCTAssertEqual(credentials.all.map(\.id), [DNSCredentials.cloudflareFirstID, "SECOND"])
        XCTAssertEqual(credentials.all.map(\.kind), [.cloudflare, .cloudflare])
        XCTAssertEqual(credentials.credential("SECOND").name, "work")
        XCTAssertEqual(credentials.selectedID, "SECOND",
                       "the account this device was publishing with has to stay the chosen one")
    }

    func testAdoptingDoesNothingOnceAListExists() async {
        let (credentials, defaults) = store("dns.migrate.twice")
        defaults.set([DNSCredentials.cloudflareFirstID],
                     forKey: DNSCredentials.Legacy.cloudflareIDsKey)
        await credentials.adoptStoredTokensIfNeeded()
        await credentials.remove(DNSCredentials.cloudflareFirstID)

        await credentials.adoptStoredTokensIfNeeded()
        XCTAssertTrue(credentials.all.isEmpty,
                      "a deleted credential came back — the old keys are being read every launch")
    }

    func testATokenFromThePerKindStoreBecomesARowNamedAfterItsProvider() async throws {
        let item = "dns-provider-token.\(DNSProviderKind.hetzner.rawValue)"
        let keychain = KeychainStore()
        try keychain.set("token-for-the-test", for: item)
        defer { try? keychain.delete(item) }

        let (credentials, _) = store("dns.migrate.kind")
        await credentials.adoptStoredTokensIfNeeded()

        let adopted = DNSCredentials.adoptedID(for: .hetzner)
        XCTAssertEqual(credentials.all.map(\.id), [adopted])
        XCTAssertEqual(credentials.credential(adopted).kind, .hetzner)
        XCTAssertEqual(credentials.credential(adopted).name, DNSProviderKind.hetzner.displayName)
        let loaded = await DNSCredentialTokenStore.load(credentials.credential(adopted))
        XCTAssertEqual(loaded, "token-for-the-test",
                       "the adopted row points at an item the token is not in")
    }

    func testADeviceWithNoTokensAnywhereAdoptsNothing() async {
        let (credentials, _) = store("dns.migrate.empty")
        await credentials.adoptStoredTokensIfNeeded()
        XCTAssertTrue(credentials.all.isEmpty)
    }
}
