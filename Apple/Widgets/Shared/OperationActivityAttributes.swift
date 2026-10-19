#if os(iOS)
import ActivityKit
import Foundation
import SwiftUI
import VPNTunnel

struct OperationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progressText: String
        var isFinished: Bool
        /// Non-nil when the run failed
        var errorMessage: String?
        var progress: Double?
        /// The app can run this operation again
        var canRetry: Bool?
        /// The first tap on stop asks; the second one stops
        var stopArmed: Bool?
        /// The script's step counter, done of total
        var step: Int?
        var steps: Int?

        init(progressText: String, isFinished: Bool,
             errorMessage: String? = nil, progress: Double? = nil, canRetry: Bool? = nil,
             stopArmed: Bool? = nil) {
            self.progressText = progressText
            self.isFinished = isFinished
            self.errorMessage = errorMessage
            self.progress = progress
            self.canRetry = canRetry
            self.stopArmed = stopArmed
        }
    }

    let title: String
    /// Which machine it is happening on
    let serverName: String
    let startedAt: Date
    /// The app's operation this card shows
    var operationID: UUID?
    /// The island offers a stop button
    var canStop: Bool?
    /// The server the operation runs on
    var deploymentID: UUID?
    /// The agent job, on cards a server started
    var jobID: String?
    /// The relay's id of the machine running the job
    var serverID: String?
}

/// What every surface says about a run, in one place
enum OperationPresentation {
    enum Outcome: Equatable {
        case running
        case succeeded
        case failed
    }

    static func outcome(_ state: OperationActivityAttributes.ContentState) -> Outcome {
        if state.errorMessage != nil { return .failed }
        return state.isFinished ? .succeeded : .running
    }

    static func symbol(_ outcome: Outcome) -> String {
        switch outcome {
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    static func tint(_ outcome: Outcome) -> Color {
        switch outcome {
        case .running: return .accentColor
        case .succeeded: return .green
        case .failed: return .orange
        }
    }

    /// The second line: what is happening, or what happened
    static func detail(_ state: OperationActivityAttributes.ContentState) -> String {
        switch outcome(state) {
        case .failed:
            return state.errorMessage ?? String(localized: "Failed")
        case .succeeded:
            return state.progressText.isEmpty ? String(localized: "Done") : state.progressText
        case .running:
            return state.progressText
        }
    }

    /// Where a tap on the card leads
    static func destination(of attributes: OperationActivityAttributes) -> AppLink.Destination {
        if let id = attributes.operationID { return .operation(id) }
        if let job = attributes.jobID { return .job(job) }
        return .app
    }

    /// Whether the elapsed clock should still be counting
    static func showsRunningClock(_ state: OperationActivityAttributes.ContentState) -> Bool {
        outcome(state) == .running
    }

    static func barValue(_ state: OperationActivityAttributes.ContentState) -> Double? {
        guard outcome(state) == .running, let progress = state.progress,
              progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    /// "3/7" while a script counts its steps
    static func stepText(_ state: OperationActivityAttributes.ContentState) -> String? {
        guard outcome(state) == .running, let step = state.step, let steps = state.steps,
              steps > 0, step <= steps else { return nil }
        return "\(step)/\(steps)"
    }

    static func percentText(_ state: OperationActivityAttributes.ContentState) -> String? {
        guard let value = barValue(state) else { return nil }
        return "\(Int((value * 100).rounded()))%"
    }

    /// One line for a finished run: done or failed
    static func headline(_ state: OperationActivityAttributes.ContentState) -> String {
        switch outcome(state) {
        case .succeeded: return String(localized: "Completed successfully")
        case .failed: return String(localized: "Failed")
        case .running: return state.progressText
        }
    }

    static func staleNote() -> String {
        String(localized: "Last update from the server. Open the app for the current progress.")
    }
}
#endif
