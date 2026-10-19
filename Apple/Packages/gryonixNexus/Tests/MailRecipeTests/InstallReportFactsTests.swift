import ServiceCatalog
import XCTest
@testable import MailRecipe

final class InstallReportFactsTests: XCTestCase {
    private func report(_ language: AppLanguage, domain: String) -> String {
        """
        \(L10nScripts.reportTitle(language))
        \(L10nScripts.domainLabel(language)) \(domain)
        \(L10nScripts.mailHostLabel(language)) mail.\(domain)
        """
    }

    func testTheDomainIsReadInEveryLanguageTheReportCanBeWrittenIn() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(InstallReportFacts.domain(inReport: report(language, domain: "example.net")),
                           "example.net",
                           "the report is generated in the owner's language: \(language.rawValue)")
        }
    }

    func testASubdomainDeploymentReadsBackWhole() {
        XCTAssertEqual(
            InstallReportFacts.domain(inReport: report(.en, domain: "b.example.net")),
            "b.example.net")
    }

    func testAReportWithoutTheLineAnswersNothing() {
        XCTAssertNil(InstallReportFacts.domain(inReport: ""))
        XCTAssertNil(InstallReportFacts.domain(inReport: "Service status:\n  docker active\n"))
    }

    func testProseAfterTheLabelIsNotTakenForADomain() {
        for value in ["not set", "example .com", "https://example.net", "example.net:443",
                      ".example.net", "example.net.", "no-dot"] {
            XCTAssertNil(InstallReportFacts.domain(inReport: "Domain: \(value)"),
                         "\"\(value)\" is not a domain")
        }
    }

    func testTheColumnPaddingIsNotPartOfTheValue() {
        XCTAssertEqual(
            InstallReportFacts.domain(inReport: "Domain:         example.net   "),
            "example.net")
    }

    func testTheAnswerIsLowercasedLikeEveryOtherHostnameHere() {
        XCTAssertEqual(InstallReportFacts.domain(inReport: "Domain: example.net"), "example.net")
    }
}
