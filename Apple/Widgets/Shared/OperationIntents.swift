#if os(iOS)
import AppIntents
import Foundation

/// What the operation card's buttons act on
@MainActor
enum OperationIntents {
    /// Set once, by the app, at launch
    static var retry: ((UUID) async -> Void)?
    static var stop: ((UUID) async -> Void)?
    /// Stops a server job by its id and machine
    static var stopJob: ((String, String) async -> Void)?
}

/// The stop button of a card a server started
@available(iOS 17.0, *)
struct StopJobIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    static var description = IntentDescription("Stops a running server operation.")

    @Parameter(title: "Job")
    var jobID: String

    @Parameter(title: "Server")
    var serverID: String

    init() {}

    init(jobID: String, serverID: String) {
        self.jobID = jobID
        self.serverID = serverID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await OperationIntents.stopJob?(jobID, serverID)
        return .result()
    }
}

/// The island's stop button: once to ask, twice to stop
@available(iOS 17.0, *)
struct StopOperationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    static var description = IntentDescription("Stops a running server operation.")

    @Parameter(title: "Operation")
    var operationID: String

    init() {}

    init(operationID: UUID) {
        self.operationID = operationID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: operationID) {
            await OperationIntents.stop?(id)
        }
        return .result()
    }
}

/// The failed card's "Try again" button
@available(iOS 17.0, *)
struct RetryOperationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Try again"
    static var description = IntentDescription("Runs a failed server operation once more.")

    @Parameter(title: "Operation")
    var operationID: String

    init() {}

    init(operationID: UUID) {
        self.operationID = operationID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: operationID) {
            await OperationIntents.retry?(id)
        }
        return .result()
    }
}

/// The VPN card's "Disconnect" button
@available(iOS 17.0, *)
struct DisconnectTunnelFromCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Disconnect the VPN"
    static var description = IntentDescription("Takes down the tunnel running on this device.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await TunnelIntents.target?.intentIslandStop()
        return .result()
    }
}
#endif
