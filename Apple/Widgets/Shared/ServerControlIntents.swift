#if !os(tvOS)
import AppIntents
import Foundation

/// What the server control's button acts on
@MainActor
enum ServerControlIntents {
    /// Set once, by the app, at launch
    static var openServer: ((UUID) -> Void)?
}

@available(iOS 18.0, macOS 26.0, *)
struct ServerControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Server"
    static var description = IntentDescription("Which server the button opens.")

    @Parameter(title: "Server")
    var server: ServerChoice?

    init() {}
}

@available(iOS 18.0, macOS 26.0, *)
struct OpenServerFromControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open server"
    static var description = IntentDescription("Opens the app on a server.")
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverID: String

    init() {}
    init(serverID: UUID?) { self.serverID = serverID?.uuidString ?? "" }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: serverID) { ServerControlIntents.openServer?(id) }
        return .result()
    }
}
#endif
