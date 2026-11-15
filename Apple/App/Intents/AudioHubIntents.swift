import AppIntents
import Foundation
import ServerControl
import ServiceCatalog

/// Finds a server's deployment that runs the audio hub
@MainActor
enum AudioHubIntentRunner {
    static func model(for server: ServerEntity,
                      deployments: [Deployment] = IntentFleet.loadDeployments()) throws -> DashboardViewModel {
        guard let deployment = deployments.first(where: { $0.id == server.id }),
              deployment.services.contains(.odio), deployment.usesAgent else {
            throw IntentFailure(message: UIL10n.string("This server has no audio hub."))
        }
        return DashboardViewModel(deployment: deployment)
    }
}

struct SetAudioHubVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set audio hub volume"
    static var description = IntentDescription("Sets the volume of the audio hub on a server at home.")
    static var openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity

    @Parameter(title: "Volume", inclusiveRange: (0, 100))
    var percent: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try AudioHubIntentRunner.model(for: server)
        try await model.odio("POST", "/audio/server/volume", body: AudioHubParser.volumeBody(Double(percent) / 100))
        return .result(dialog: IntentDialog(stringLiteral: UIL10n.string("Volume set to %d%%.", percent)))
    }
}

struct AudioHubPlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or pause the audio hub"
    static var description = IntentDescription("Plays or pauses whatever the audio hub on a server is playing.")
    static var openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try AudioHubIntentRunner.model(for: server)
        let players = AudioHubParser.players(try await model.odio("GET", "/players"))
        guard let player = players.first(where: \.isPlaying) ?? players.first else {
            throw IntentFailure(message: UIL10n.string("Nothing is playing"))
        }
        try await model.odio("POST", "/players/\(player.busName)/play_pause")
        let done = player.isPlaying ? "Paused." : "Playing."
        return .result(dialog: IntentDialog(stringLiteral: UIL10n.string(done)))
    }
}
