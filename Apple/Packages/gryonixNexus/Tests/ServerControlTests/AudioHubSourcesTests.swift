import XCTest

@testable import ServerControl

final class AudioHubSourcesTests: XCTestCase {
    func testTheReadingTellsWhichPlayersAreInstalled() {
        let both = AudioHubSources(json: #"{"spotify.name":"Living room","spotify.bitrate":"320","airplay.name":"%h"}"#)
        XCTAssertTrue(both.hasSpotify)
        XCTAssertTrue(both.hasAirPlay)
        let none = AudioHubSources(json: "{}")
        XCTAssertFalse(none.hasSpotify)
        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(AudioHubSources(json: "not json").isEmpty)
    }

    func testOnlyEditedValuesAreSent() {
        let saved = AudioHubSources(values: ["spotify.name": "Kitchen", "spotify.bitrate": "320", "airplay.name": "%h"])
        var edited = saved
        XCTAssertNil(edited.changes(from: saved))
        edited.values["spotify.name"] = "Living room"
        edited.values["spotify.bitrate"] = "160"
        XCTAssertEqual(edited.changes(from: saved), #"{"spotify.bitrate":"160","spotify.name":"Living room"}"#)
    }
}
