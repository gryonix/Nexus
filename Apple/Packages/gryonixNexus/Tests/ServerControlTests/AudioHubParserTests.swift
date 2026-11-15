import XCTest
@testable import ServerControl

final class AudioHubParserTests: XCTestCase {
    func testOutputsPlayersAndServicesComeFromOdioBodies() {
        let outputs = AudioHubParser.outputs(#"[{"id":0,"name":"alsa_output.hdmi","description":"HDMI","volume":0.5,"muted":false,"default":true}]"#)
        XCTAssertEqual(outputs, [.init(name: "alsa_output.hdmi", title: "HDMI", volume: 0.5, muted: false, isDefault: true)])

        let players = AudioHubParser.players(#"[{"bus_name":"org.mpris.MediaPlayer2.mpd","identity":"Music Player Daemon","playback_status":"Playing","metadata":{"xesam:title":"Song","xesam:artist":"Band"},"capabilities":{"can_go_next":true}}]"#)
        XCTAssertEqual(players.first?.title, "Song")
        XCTAssertEqual(players.first?.artist, "Band")
        XCTAssertTrue(players.first?.isPlaying ?? false)
        XCTAssertFalse(players.first?.canGoPrevious ?? true)

        let services = AudioHubParser.services(#"[{"name":"bluetooth.service","scope":"system","running":true},{"name":"mpd.service","scope":"user","running":false,"exists":true,"description":"Music Player Daemon"},{"name":"spotifyd.service","scope":"user","exists":false}]"#)
        XCTAssertEqual(services, [.init(unit: "mpd.service", title: "Music Player Daemon", running: false)])
    }

    func testServerAndBluetoothStateAndVolumeBody() {
        var state = AudioHubState()
        AudioHubParser.apply(server: #"{"volume":0.8,"muted":true}"#, to: &state)
        AudioHubParser.apply(bluetooth: #"{"powered":true,"pairing_active":false}"#, to: &state)
        XCTAssertEqual(AudioHubState.percent(state.volume), 80)
        XCTAssertTrue(state.muted)
        XCTAssertTrue(state.bluetoothPowered)
        XCTAssertEqual(AudioHubParser.volumeBody(1.4), #"{"volume":1.00}"#)
        AudioHubParser.apply(server: "not json", to: &state)
        XCTAssertTrue(state.muted)
    }
}
