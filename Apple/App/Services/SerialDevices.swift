import AgentClient
import Foundation
import ServerControl

/// One USB serial adapter, as the stick picker shows it
struct SerialDeviceOption: Identifiable, Equatable, Sendable {
    /// The by-id path, which is what gets stored
    let path: String
    /// What it points at right now, shown but never stored
    let target: String
    let label: String

    var id: String { path }
}

/// What the stick picker shows right now
enum SerialListing: Equatable {
    case idle
    case loading
    /// `directoryPresent` false — the machine never had a USB serial adapter
    case loaded([SerialDeviceOption], directoryPresent: Bool)
    case failed(String)
}

/// The host's USB serial adapters, read through the agent
@available(macOS 15.0, *)
enum SerialDevices {
    /// What one call brings back
    struct Listing: Sendable {
        var devices: [SerialDeviceOption] = []
        /// False when the machine never had a USB serial adapter
        var directoryPresent = false
        var failure: String?
    }

    static func list(deployment: Deployment) async -> Listing {
        guard deployment.usesAgent else {
            return Listing(failure: String(localized: "This server has no agent to ask."))
        }
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            let answer = try await session.client.listSerialDevices()
            return Listing(devices: answer.devices.map {
                SerialDeviceOption(path: $0.path, target: $0.target, label: $0.label)
            }, directoryPresent: answer.directoryPresent)
        } catch {
            return Listing(failure: message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let agent = error as? AgentError, case .rpc(_, let text) = agent { return text }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
