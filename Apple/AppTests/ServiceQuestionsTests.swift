import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class ServiceQuestionsTests: XCTestCase {
    private func model() -> ServiceConfigViewModel {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "example.com"
        model.publicIP = "203.0.113.10"
        return model
    }

    private func raised(_ services: Set<ServiceID>, topology: Topology = .singleHost,
                        scope: DeploymentScope = .publicInternet) -> [ServiceQuestion] {
        ServiceQuestions.raised(by: services, topology: topology, scope: scope)
    }

    func testADeploymentWithNoGameServerRaisesNothing() {
        XCTAssertEqual(raised([.mailcow, .wireguardVPN, .nextcloud]), [])
    }

    func testEachGameServerRaisesItsOwnLicenseAndOnlyItsOwn() {
        XCTAssertEqual(raised([.minecraftJava]), [.minecraftJavaEULA])
        XCTAssertEqual(raised([.minecraftBedrock]), [.minecraftBedrockEULA])
        XCTAssertEqual(raised([.minecraftJava, .minecraftBedrock]),
                       [.minecraftJavaEULA, .minecraftBedrockEULA])
    }

    func testTheHubAsksOnlyWhereTheMachineCouldBeAnywhere() {
        XCTAssertEqual(raised([.homeAssistant]), [.machineAtHome])
        XCTAssertEqual(raised([.homeAssistant], scope: .cloudflareTunnel), [.machineAtHome])
        XCTAssertEqual(raised([.homeAssistant], scope: .meshOnly), [.machineAtHome])
        XCTAssertEqual(raised([.homeAssistant], scope: .localOnly), [])
        XCTAssertEqual(raised([.homeAssistant], scope: .dynamicDNS), [])
        XCTAssertEqual(raised([.homeAssistant], topology: .vpsRelayWithHomeBackend), [])
    }

    func testTheHomeAnswerReachesTheGenerator() {
        let model = model()
        model.extraServices = [.homeAssistant]
        XCTAssertFalse(model.makeServiceSettings().machineAtHome)
        model.questionBinding(.machineAtHome).wrappedValue = true
        XCTAssertTrue(model.makeServiceSettings().machineAtHome)
    }

    func testAnsweringWritesTheSettingTheGeneratorReads() {
        let model = model()
        model.extraServices = [.minecraftJava, .minecraftBedrock]

        XCTAssertFalse(model.makeServiceSettings().minecraftJavaAcceptsEULA)
        XCTAssertFalse(model.makeServiceSettings().minecraftBedrockAcceptsEULA)

        model.questionBinding(.minecraftJavaEULA).wrappedValue = true
        XCTAssertTrue(model.makeServiceSettings().minecraftJavaAcceptsEULA)
        XCTAssertFalse(model.makeServiceSettings().minecraftBedrockAcceptsEULA,
                       "one answer must not answer the other question")

        model.questionBinding(.minecraftBedrockEULA).wrappedValue = true
        XCTAssertTrue(model.makeServiceSettings().minecraftBedrockAcceptsEULA)
    }

    func testIsAnsweredFollowsTheAnswer() {
        let model = model()
        model.extraServices = [.minecraftJava]
        XCTAssertFalse(model.isAnswered(.minecraftJavaEULA))
        model.questionBinding(.minecraftJavaEULA).wrappedValue = true
        XCTAssertTrue(model.isAnswered(.minecraftJavaEULA))
    }

    func testEveryServiceTheValidatorRefusesOnHasAQuestion() throws {
        let validator = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // AppTests
            .deletingLastPathComponent()          // Apple
            .appendingPathComponent("Packages/gryonixNexus/Sources/MailRecipe/MailInputValidator.swift")
        let source = try String(contentsOf: validator, encoding: .utf8)

        let pattern = #"input\.services\.contains\(\.(\w+)\), !settings\."#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertFalse(matches.isEmpty,
                       "the refusal shape changed — this test stopped reading anything")

        func flat(_ s: String) -> String { s.replacingOccurrences(of: "-", with: "").lowercased() }
        let asked = Set(ServiceQuestion.allCases.map { flat($0.service.rawValue) })
        for match in matches {
            let name = String(source[Range(match.range(at: 1), in: source)!])
            XCTAssertTrue(asked.contains(flat(name)),
                          "MailInputValidator refuses on \(name) and no ServiceQuestion asks about it")
        }
    }
}
