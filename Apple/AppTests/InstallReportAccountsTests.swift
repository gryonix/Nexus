import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// Which report sections become a login
final class InstallReportAccountsTests: XCTestCase {
    private func accounts(_ text: String) -> [SimpleAccount] {
        SimpleAccount.accounts(from: InstallReportParser.sections(from: text))
    }

    /// A broker speaks MQTT and has no web address
    func testTheBrokerBecomesALoginWithoutAWebAddress() throws {
        let report = """
        Mosquitto:    \(L10nServices.mosquittoNetworkAddress(.en)):1883
          \(L10nServices.mosquittoAccountsLabel(.en)): homeassistant, zigbee2mqtt
          \(L10nServices.passwordGeneratedOnServerLabel(.en)): s3cret
        """
        let account = try XCTUnwrap(accounts(report).first)
        XCTAssertEqual(account.title, "Mosquitto")
        XCTAssertEqual(account.login, "homeassistant, zigbee2mqtt")
        XCTAssertEqual(account.password, "s3cret")
        XCTAssertNil(account.website)
    }

    /// The address can sit under another label
    func testASectionNamingItsAddressWebmailStillCarriesIt() throws {
        let report = """
        Docker Mailserver:
          \(L10nServices.webmailLabel(.en)):     https://mail.example.com
          \(L10nServices.firstMailboxLabel(.en)): admin@example.com
          \(L10nServices.passwordGeneratedOnServerLabel(.en)): s3cret
        """
        let account = try XCTUnwrap(accounts(report).first)
        XCTAssertEqual(account.website, "https://mail.example.com")
        XCTAssertEqual(account.password, "s3cret")
    }

    /// A site with no credential is still offered
    func testASiteWithoutACredentialIsStillOffered() throws {
        let account = try XCTUnwrap(accounts("Homepage: https://home.example.com").first)
        XCTAssertEqual(account.website, "https://home.example.com")
        XCTAssertNil(account.password)
    }

    /// Neither a site nor a credential is not a login
    func testASectionWithNeitherAnAddressNorASecretIsNotALogin() {
        XCTAssertTrue(accounts("Firewall:\n  Open ports: 80, 443").isEmpty)
    }
}
