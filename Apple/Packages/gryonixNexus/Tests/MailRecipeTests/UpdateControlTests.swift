import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class UpdateControlTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    // MARK: - Generation helpers

    private func input(_ services: Set<ServiceID>,
                       topology: Topology = .singleHost) throws -> MailRecipeInput {
        let servers: [ServerNode] = topology == .singleHost
            ? [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                          distribution: .debian)]
            : [ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                          vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
               ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"),
                          distribution: .debian)]
        return MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: topology,
            servers: servers,
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: appKey),
            services: services,
            // Scenario B holds 51820 for the relay tunnel.
            serviceSettings: ServiceSettings(wireguardVPNPort: 51821)
        )
    }

    private func script(_ services: Set<ServiceID>, file: String = "setup-mail-server.sh",
                        topology: Topology = .singleHost) throws -> String {
        let bundle = try MailRecipe().generate(from: try input(services, topology: topology))
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == file }?.contents,
                             bundle.artifacts.map(\.fileName).joined(separator: ", "))
    }

    private func wrapperBody(in script: String) -> String {
        let start = "cat > \(UpdateControlSections.scriptPath) <<'EOF_UPDATE_CTL'"
        guard let range = script.range(of: start),
              let end = script.range(of: "\nEOF_UPDATE_CTL\n", range: range.upperBound..<script.endIndex)
        else { return "" }
        return String(script[range.upperBound..<end.lowerBound])
    }

    private func serviceTable(in wrapper: String) -> [String: [String: String]] {
        var table: [String: [String: String]] = [:]
        for rawLine in wrapper.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let paren = line.firstIndex(of: ")"), line.contains("PROJECT='") else { continue }
            let label = String(line[line.startIndex..<paren])
            guard label.allSatisfy({ ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == "-" })
            else { continue }
            var fields: [String: String] = [:]
            for key in ["PROJECT", "DIR", "BACKUP_TARGET", "IMAGES"] {
                guard let opening = line.range(of: "\(key)='"),
                      let close = line[opening.upperBound...].firstIndex(of: "'") else { continue }
                fields[key] = String(line[opening.upperBound..<close])
            }
            table[label] = fields
        }
        return table
    }

    private var context: ServiceContext {
        ServiceContext(domain: "example.com", sshUser: "admin",
                       settings: ServiceSettings(wireguardVPNPort: 51821))
    }

    private let mixed: Set<ServiceID> = [.nextcloud, .immich, .vaultwarden, .jellyfin,
                                         .gitlab, .amneziaWG]

    // MARK: - The table

    func testEveryPullUpdatedServiceStatesItsProjectDirectoryAndImages() throws {
        let table = serviceTable(in: wrapperBody(in: try script(mixed)))
        for service in ServiceRegistry.all where mixed.contains(service.id) {
            let spec = service.updateSpec(context)
            guard spec.flavour == .composePull else { continue }
            let arm = try XCTUnwrap(table[service.id.rawValue],
                                    "\(service.id.rawValue) can be pulled but has no arm: \(table.keys)")
            guard case .docker(let project) = service.runtime else { return XCTFail("not docker") }
            XCTAssertEqual(arm["PROJECT"], project)
            XCTAssertEqual(arm["DIR"], service.composeFile(context)?.directory,
                           "\(service.id.rawValue) must be updated from its own compose directory")
            XCTAssertEqual(arm["IMAGES"], spec.images.joined(separator: " "),
                           "\(service.id.rawValue) pulls a different set of images than it declares")
        }
    }

    func testTheTableHoldsNothingThisDeploymentDoesNotInstall() throws {
        let table = serviceTable(in: wrapperBody(in: try script([.nextcloud, .amneziaWG])))
        XCTAssertEqual(Set(table.keys), ["nextcloud", "amnezia-wg"], "\(table.keys)")
    }

    func testAServiceThatShipsItsOwnUpdaterIsNeverPulled() throws {
        for id in [ServiceID.mailcow, .gitlab] {
            let wrapper = wrapperBody(in: try script([id, .nextcloud]))
            XCTAssertFalse(serviceTable(in: wrapper).keys.contains(id.rawValue),
                           "\(id.rawValue) must not have an arm that pulls its images")
            XCTAssertTrue(wrapper.contains("SELF_MANAGED='\(id.rawValue)'"),
                          "\(id.rawValue) must be named as self-managed")
        }
    }

    func testImagesBuiltOnTheServerAreNotPolled() throws {
        let wrapper = wrapperBody(in: try script([.openVPN, .nextcloud]))
        XCTAssertFalse(wrapper.contains(":local"),
                       "an image built by our own setup has no registry to be checked against")
        XCTAssertFalse(serviceTable(in: wrapper).keys.contains(ServiceID.vpnPanel.rawValue))
    }

    // MARK: - The backup that comes first

    func testAnUpdateBacksUpThroughTheBackupWrapperBeforeItPulls() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        XCTAssertTrue(wrapper.contains("BACKUP_CTL='\(BackupControlSections.scriptPath)'"),
                      "the update must drive the one wrapper that owns backups")
        let body = try XCTUnwrap(wrapper.range(of: "gd_update_service() {")
            .map { String(wrapper[$0.lowerBound...]) })
        let backupCall = try XCTUnwrap(body.range(of: "\"$BACKUP_CTL\" backup"))
        let pull = try XCTUnwrap(body.range(of: "docker compose -p \"$PROJECT\" pull"))
        XCTAssertLessThan(backupCall.lowerBound, pull.lowerBound,
                          "the backup has to happen before anything is pulled")
        XCTAssertTrue(body.contains("the backup of $svc failed, so the update was not applied"))
    }

    func testEveryBackupTargetTheUpdateWrapperAsksForExistsInTheBackupWrapper() throws {
        let text = try script(mixed)
        let table = serviceTable(in: wrapperBody(in: text))
        let backupArms = Set(text.split(separator: "\n").compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(";;"), let lockRange = line.range(of: "gd_with_lock 'backup-"),
                  let closeQuote = line[lockRange.upperBound...].firstIndex(of: "'") else { return nil }
            return String(line[lockRange.upperBound..<closeQuote])
        })
        XCTAssertFalse(backupArms.isEmpty, "no backup dispatch arms were found at all")
        for (service, fields) in table {
            let target = fields["BACKUP_TARGET"] ?? ""
            guard !target.isEmpty else { continue }
            XCTAssertTrue(backupArms.contains(target),
                          "\(service) would ask the backup wrapper for '\(target)', which it has no arm for")
        }
    }

    // MARK: - The answers

    func testACheckThatCouldNotAnswerIsNeverReportedAsCurrent() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        let unknownTest = try XCTUnwrap(wrapper.range(of: #"if [ -n "$unknown" ]; then"#))
        let unknownPrint = try XCTUnwrap(wrapper.range(of: "'\(UpdateControlSections.unknownMarker)' \"$svc\" \"$unknown\"",
                                                       range: unknownTest.upperBound..<wrapper.endIndex))
        let currentPrint = try XCTUnwrap(wrapper.range(of: "'\(UpdateControlSections.currentMarker)' \"$svc\"",
                                                       range: unknownPrint.upperBound..<wrapper.endIndex))
        let between = String(wrapper[unknownPrint.upperBound..<currentPrint.lowerBound])
        XCTAssertTrue(between.contains(#"elif [ "$moved" -eq 0 ]; then"#),
                      "the current marker must sit in the else-branch of the unknown test, not next to it")
        XCTAssertEqual(wrapper.components(separatedBy: "'\(UpdateControlSections.currentMarker)'").count - 1, 1,
                       "there must be exactly one place that can print 'up to date'")
        for reason in ["registry_unreachable", "not_pulled", "docker_unavailable"] {
            XCTAssertTrue(wrapper.contains("'\(UpdateControlSections.unknownMarker)' \"$svc\" '\(reason)'")
                          || wrapper.contains("\"$unknown\""),
                          "\(reason) must be reported as unknown")
        }
    }

    func testTheRollbackCapturesThePreviousImageBeforePulling() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        let body = try XCTUnwrap(wrapper.range(of: "gd_update_service() {")
            .map { String(wrapper[$0.lowerBound...]) })
        let capture = try XCTUnwrap(body.range(of: #"old="$(gd_image_id "$img")""#))
        let pull = try XCTUnwrap(body.range(of: "docker compose -p \"$PROJECT\" pull"))
        XCTAssertLessThan(capture.lowerBound, pull.lowerBound,
                          "after the pull the tag points elsewhere; the previous id has to be read first")
        XCTAssertTrue(wrapper.contains(#"docker tag "$old" "$img""#),
                      "the rollback is putting the tag back — no registry, no network")
        XCTAssertTrue(wrapper.contains("'\(UpdateControlSections.rolledBackMarker)' \"$svc\" \"$reason\""),
                      "a rollback has to say it happened, and why")
    }

    func testEveryFailingReturnInTheUpdateBodyIsRecorded() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        let body = try XCTUnwrap(wrapper.range(of: "gd_update_service_locked() {")
            .map { String(wrapper[$0.lowerBound...]) })
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let end = try XCTUnwrap(lines.dropFirst().firstIndex { $0 == "}" })
        var checked = 0
        for index in 1..<end where lines[index].trimmingCharacters(in: .whitespaces) == "return 1" {
            checked += 1
            let window = lines[max(0, index - 6)..<index].joined(separator: "\n")
            XCTAssertTrue(window.contains(UpdateControlSections.failedMarker)
                            || window.contains(UpdateControlSections.rolledBackMarker),
                          "a failed update at line \(index) of gd_update_service records nothing, "
                            + "so a scheduled run that hit it looks like a run that never happened:\n\(window)")
        }
        XCTAssertGreaterThanOrEqual(checked, 3,
                                    "the body lost its failure branches — this test would now pass on nothing")
    }

    func testTheScheduledRunIsolatesEachServiceAndStillFails() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        XCTAssertTrue(wrapper.contains("( gd_update_service \"$svc\" ) || failed=\"$failed $svc\""),
                      "each service runs in its own subshell so errexit cannot end the run")
        XCTAssertTrue(wrapper.contains(#"echo "the update failed for:$failed" >&2"#))
        XCTAssertTrue(wrapper.contains("exit 1"))
    }

    func testTheTimerAndTheAppReachTheSamePerServiceBody() throws {
        let text = try script(mixed)
        let wrapper = wrapperBody(in: text)
        XCTAssertTrue(text.contains("ExecStart=\(UpdateControlSections.scriptPath) run \(UpdateControlSections.scheduledFlag)"),
                      "the timer must call the same wrapper the app calls")
        XCTAssertEqual(wrapper.components(separatedBy: "docker compose -p \"$PROJECT\" pull").count - 1, 1,
                       "there must be exactly one place that pulls")
    }

    // MARK: - Arguments and the whitelist

    func testTheSudoersLineExistsExactlyWhereTheWrapperDoesAndPinsNoArguments() throws {
        let withUpdates = try script(mixed)
        XCTAssertTrue(withUpdates.contains("admin ALL=(ALL) NOPASSWD: \(UpdateControlSections.scriptPath)\n"),
                      "a command does not exist without its whitelist line")
        XCTAssertTrue(withUpdates.contains("cat > \(UpdateControlSections.scriptPath) <<"))

        let noUpdates = try script([.openVPN])
        XCTAssertFalse(noUpdates.contains("NOPASSWD: \(UpdateControlSections.scriptPath)"),
                       "nothing here can be updated by a pull, so nothing should be whitelisted")
        XCTAssertFalse(noUpdates.contains("cat > \(UpdateControlSections.scriptPath) <<"))
    }

    func testTheWrapperValidatesItsOwnLabelBeforeAnythingElse() throws {
        let wrapper = wrapperBody(in: try script(mixed))
        XCTAssertTrue(wrapper.contains("''|*[!a-z0-9-]*) echo \"invalid service: ${1:-}\" >&2; return 2 ;;"),
                      "the label charset is the guard sudoers is relying on")
        for line in wrapper.split(separator: "\n") where line.contains("docker ") {
            XCTAssertFalse(line.contains("$svc") && line.contains("docker "),
                           "a docker invocation must not carry the caller's label: \(line)")
        }
    }

    // MARK: - Schedule, uninstall, syntax

    func testBothWrappersParseTheScheduleWithTheSameShell() throws {
        let text = try script(mixed)
        let occurrences = text.components(separatedBy: ScheduleSections.parser).count - 1
        XCTAssertEqual(occurrences, 2,
                       "the backup and update wrappers must carry the identical schedule parser")
        XCTAssertTrue(wrapperBody(in: text).contains("set-schedule \(ScheduleSections.grammar)"),
                      "the usage header must advertise the grammar the parser implements")
    }

    func testUninstallRemovesEverythingThisFeatureCreates() throws {
        let bundle = try MailRecipe().generate(from: try input(mixed, topology: .vpsRelayWithHomeBackend))
        for name in ["setup-home-server.sh", "setup-vps.sh"] {
            let text = try XCTUnwrap(bundle.artifacts.first { $0.fileName == name }?.contents)
            XCTAssertTrue(text.contains("systemctl disable --now '\(UpdateControlSections.timerName)'"),
                          "\(name): the timer outlives the services unless it is stopped")
            XCTAssertTrue(text.contains("/etc/systemd/system/\(UpdateControlSections.timerName)"),
                          "\(name): the timer unit")
            XCTAssertTrue(text.contains("/etc/systemd/system/\(UpdateControlSections.serviceName)"),
                          "\(name): the oneshot unit")
            XCTAssertTrue(text.contains("rm -f '\(UpdateControlSections.configPath)' '\(UpdateControlSections.statusPath)'"),
                          "\(name): the schedule and the record of the last run")
            XCTAssertTrue(text.contains("rm -f '\(UpdateControlSections.scriptPath)'"),
                          "\(name): the wrapper itself")
        }
    }

    func testTheRelayIsNeverGivenTheUpdateWrapper() throws {
        let bundle = try MailRecipe().generate(from: try input(mixed, topology: .vpsRelayWithHomeBackend))
        let vps = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-vps.sh" }?.contents)
        XCTAssertFalse(vps.contains("cat > \(UpdateControlSections.scriptPath) <<"))
        XCTAssertFalse(vps.contains("NOPASSWD: \(UpdateControlSections.scriptPath)"))
    }

    #if os(macOS)
    func testTheGeneratedWrapperIsValidBash() throws {
        for services in [mixed, [ServiceID.nextcloud], [.adguardHome]] {
            let body = wrapperBody(in: try script(services))
            XCTAssertFalse(body.isEmpty)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gryonixnexus-update-ctl-\(UUID().uuidString).sh")
            try body.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", url.path]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, "bash -n failed:\n\(message)")
        }
    }
    #endif

    /// The literals the app parses
    func testTheMarkersAndPathsAreTheOnesTheAppExpects() throws {
        XCTAssertEqual(UpdateControlSections.scriptPath, "/opt/gryonixnexus-update-ctl.sh")
        XCTAssertEqual(UpdateControlSections.doneMarker, "GRYONIXNEXUS_UPDATE_CTL_DONE")
        XCTAssertEqual(UpdateControlSections.availableMarker, "GRYONIXNEXUS_UPDATE_AVAILABLE")
        XCTAssertEqual(UpdateControlSections.currentMarker, "GRYONIXNEXUS_UPDATE_CURRENT")
        XCTAssertEqual(UpdateControlSections.unknownMarker, "GRYONIXNEXUS_UPDATE_UNKNOWN")
        XCTAssertEqual(UpdateControlSections.updatedMarker, "GRYONIXNEXUS_UPDATE_DONE")
        XCTAssertEqual(UpdateControlSections.rolledBackMarker, "GRYONIXNEXUS_UPDATE_ROLLED_BACK")
        XCTAssertEqual(UpdateControlSections.failedMarker, "GRYONIXNEXUS_UPDATE_FAILED")
        XCTAssertEqual(UpdateControlSections.configPath, "/etc/gryonixnexus/autoupdate.conf")

        let wrapper = wrapperBody(in: try script(mixed))
        for marker in ["GRYONIXNEXUS_UPDATE_CTL_DONE", "GRYONIXNEXUS_UPDATE_AVAILABLE",
                       "GRYONIXNEXUS_UPDATE_CURRENT", "GRYONIXNEXUS_UPDATE_UNKNOWN",
                       "GRYONIXNEXUS_UPDATE_DONE", "GRYONIXNEXUS_UPDATE_ROLLED_BACK",
                       "GRYONIXNEXUS_UPDATE_FAILED"] {
            XCTAssertTrue(wrapper.contains(marker), "the wrapper never prints \(marker)")
        }
        XCTAssertTrue(wrapper.contains("CONFIG='/etc/gryonixnexus/autoupdate.conf'"))
        XCTAssertTrue(wrapper.contains("SCHEDULE=$schedule"))
        XCTAssertTrue(wrapper.contains("SERVICES='${checked# }'"))
    }
}
