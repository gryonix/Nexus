import ServiceCatalog
import XCTest

final class ShairportOptionsTests: XCTestCase {
    private func config(_ options: String) -> String {
        ShairportSyncService.configContents(ServiceContext(domain: "example.com", sshUser: "admin",
                                                           settings: ServiceSettings(shairportOptions: options)))
    }

    func testOptionsBecomeAConfigAndBadValuesAreDropped() {
        let text = config("interpolation=soxr;output_rate=44100;audio_backend_latency_offset_in_seconds=-0.15;volume_range_db=500;mixer_control_name=PCM;output_format=S16\";x;session_timeout=1e3")
        XCTAssertEqual(text, "general = {\n  interpolation = \"soxr\";\n  audio_backend_latency_offset_in_seconds = -0.15;\n};\nalsa = {\n  mixer_control_name = \"PCM\";\n  output_rate = 44100;\n};\n")
        XCTAssertEqual(config(""), "general = {\n};\nalsa = {\n};\n")
    }

    func testTheTextRoundTripsInFileOrder() {
        let text = ShairportSyncService.optionsText(["output_rate": "44100", "interpolation": "soxr", "session_timeout": ""])
        XCTAssertEqual(text, "interpolation=soxr;output_rate=44100")
        XCTAssertEqual(ShairportSyncService.parsedOptions(text).map(\.key), ["interpolation", "output_rate"])
    }

    func testTheComposeMountsTheConfig() {
        let context = ServiceContext(domain: "example.com", sshUser: "admin", settings: ServiceSettings())
        let compose = ShairportSyncService().composeFile(context)!.composeContents
        XCTAssertTrue(compose.contains("- ./shairport-sync.conf:/etc/shairport-sync.conf:ro"))
        let steps = ShairportSyncService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("cat > shairport-sync.conf <<'EOF_SHAIRPORT_CONF'\ngeneral = {\n};\nalsa = {\n};\nEOF_SHAIRPORT_CONF"))
    }

    func testHDMIVolumeForcesTheSliderOffAndSharesTheMetadataPipe() {
        let options = "cec_volume=yes;cec_volume_min=5;cec_volume_max=60"
        XCTAssertEqual(config(options), "general = {\n  ignore_volume_control = \"yes\";\n};\nalsa = {\n};\nmetadata = {\n  enabled = \"yes\";\n  include_cover_art = \"no\";\n  pipe_name = \"/run/shairport-sync/metadata\";\n  pipe_timeout = 5000;\n};\n")
        XCTAssertEqual(config("cec_volume=no"), "general = {\n};\nalsa = {\n};\n")
        let context = ServiceContext(domain: "example.com", sshUser: "admin",
                                     settings: ServiceSettings(shairportOptions: options))
        XCTAssertTrue(ShairportSyncService().composeFile(context)!.composeContents
            .contains(":/etc/shairport-sync.conf:ro\n      - /run/shairport-sync:/run/shairport-sync\n    command:"))
        XCTAssertEqual(ShairportSyncService.cecVolume(context), .init(enabled: true, lowest: 5, highest: 60))
    }

    func testABadHDMIRangeFallsBackAndKeepsTheGap() {
        let bad = ServiceContext(domain: "example.com", sshUser: "admin",
                                 settings: ServiceSettings(shairportOptions: "cec_volume=yes;cec_volume_min=50;cec_volume_max=10"))
        XCTAssertEqual(ShairportSyncService.cecVolume(bad), .init(enabled: true, lowest: 9, highest: 10))
        let none = ServiceContext(domain: "example.com", sshUser: "admin", settings: ServiceSettings())
        XCTAssertEqual(ShairportSyncService.cecVolume(none), .init(enabled: false, lowest: 1, highest: 40))
        let wakes = ServiceContext(domain: "example.com", sshUser: "admin",
                                   settings: ServiceSettings(shairportOptions: "cec_volume=yes;cec_tv_wakes=yes"))
        XCTAssertFalse(ShairportSyncService.cecVolume(wakes).tvOff)
        XCTAssertEqual(ShairportSyncService.cecVolume(none).offDelay, 2)
        let timed = ServiceContext(domain: "example.com", sshUser: "admin", settings: ServiceSettings(
            shairportOptions: "cec_volume=yes;cec_tv_wait=30;cec_off_delay=5;cec_grace=999;cec_keep_connected=yes"))
        let custom = ShairportSyncService.cecVolume(timed)
        XCTAssertEqual([custom.tvWait, custom.offDelay, custom.grace], [30, 5, 15])
        XCTAssertFalse(custom.disconnect)
    }
}
