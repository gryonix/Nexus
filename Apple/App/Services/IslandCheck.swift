#if os(iOS) && DEBUG
import ServerControl
import UIKit

/// A sample operation card, only in debug builds
@MainActor
enum IslandCheck {
    static let steps = 6
    /// Fits the app's half minute in the background
    static let localStepSeconds = 3
    private static var isRunning = false

    /// Who moves the card
    enum Driver: Equatable {
        /// A server, through the relay; works with the app closed
        case server(String)
        /// This app: the card stops once iOS suspends it
        case app
    }

    /// A server moves the card, else this app does
    static func run() async -> Driver? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        let title = UIL10n.string("Test card")
        let id = UUID()
        OperationActivities.shared.start(id: id, title: title, serverName: UIDevice.current.name,
                                         progressText: step(1), progress: progress(1))
        if let token = await OperationActivities.shared.pushToken(of: id),
           let server = await serverDriven(token: token, title: title) {
            OperationActivities.shared.remember(id, followsJob: "island-check")
            return .server(server)
        }
        OperationActivities.shared.dismissCard(of: id)
        await runHere(title)
        return .app
    }

    /// The first agent server whose notifications go through a relay
    private static func serverDriven(token: String, title: String) async -> String? {
        guard #available(macOS 15.0, *) else { return nil }
        let deployments = (try? FileDeploymentStore().load()) ?? []
        for deployment in deployments where deployment.usesAgent {
            guard let session = try? await AgentConnection.open(deployment: deployment, shared: true),
                  let answer = try? await session.client.testLiveActivity(token: token, title: title),
                  answer.ok else { continue }
            return deployment.name
        }
        return nil
    }

    private static func runHere(_ title: String) async {
        let island = IslandRun(title: title, serverName: UIDevice.current.name,
                               progressText: step(1), progress: progress(1))
        for number in 2...steps {
            try? await Task.sleep(for: .seconds(localStepSeconds))
            island.update(step(number), progress: progress(number))
        }
        try? await Task.sleep(for: .seconds(localStepSeconds))
        island.finish(step(steps))
    }

    private static func step(_ number: Int) -> String {
        UIL10n.string("Step %lld of %lld", number, steps)
    }

    private static func progress(_ number: Int) -> Double {
        Double(number) / Double(steps)
    }
}
#endif
