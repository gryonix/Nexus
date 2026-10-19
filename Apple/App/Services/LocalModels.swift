import AgentClient
import ServerControl
import ServiceCatalog
import Foundation

@available(macOS 15.0, *)
enum LocalModels {
    /// What one call brings back
    struct Listing: Sendable {
        var models: [Gryonixnexusd_V1_Model] = []
        var enginePresent = false
        var path = ""
        var freeBytes: UInt64 = 0
        var totalBytes: UInt64 = 0
        var reachedServer = false
        var failure: String?

        init() {}

        init(_ list: Gryonixnexusd_V1_ModelList) {
            models = list.models
            enginePresent = list.enginePresent
            path = list.path
            freeBytes = list.diskFreeBytes
            totalBytes = list.diskTotalBytes
            reachedServer = true
        }
    }

    /// One step of a fetch, as the screen shows it
    struct Progress: Sendable {
        var text = ""
        var completed: UInt64 = 0
        var total: UInt64 = 0
        /// The host's name for the run
        var jobID = ""
        var finished = false
        var listing: Listing?

        var fraction: Double? {
            guard total > 0 else { return nil }
            return min(1, Double(completed) / Double(total))
        }
    }

    private static func message(for error: Error) -> String {
        if let agent = error as? AgentError, case .rpc(_, let text) = agent { return text }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func list(deployment: Deployment) async -> Listing {
        guard deployment.usesAgent else { return Listing() }
        var result = Listing()
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            result = Listing(try await session.client.listModels())
        } catch {
            result.failure = message(for: error)
        }
        return result
    }

    @discardableResult
    static func delete(_ name: String, deployment: Deployment) async -> Listing {
        guard deployment.usesAgent else { return Listing() }
        var result = Listing()
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            result = Listing(try await session.client.deleteModel(name: name))
        } catch {
            result.failure = message(for: error)
        }
        return result
    }

    static func stop(jobID: String, deployment: Deployment) async -> String? {
        guard deployment.usesAgent, !jobID.isEmpty else { return nil }
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            _ = try await session.client.cancelJob(jobID: jobID)
            return nil
        } catch {
            return message(for: error)
        }
    }

    /// Fetch one, yielding progress as it arrives
    static func pull(_ name: String, deployment: Deployment) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            let task = Task {
                guard deployment.usesAgent else {
                    continuation.finish()
                    return
                }
                do {
                    let session = try await AgentConnection.open(deployment: deployment)
                    defer { Task { await session.runner.disconnect() } }
                    for try await event in session.client.pullModel(name: name) {
                        var step = Progress()
                        step.text = event.text
                        step.completed = event.completedBytes
                        step.total = event.totalBytes
                        step.jobID = event.jobID
                        step.finished = event.phase == .completed
                        if event.hasList {
                            step.listing = Listing(event.list)
                        }
                        continuation.yield(step)
                    }
                } catch {
                    var step = Progress()
                    step.text = message(for: error)
                    step.finished = true
                    continuation.yield(step)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
