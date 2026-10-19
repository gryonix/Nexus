import Foundation

/// Share of an agent build done, by the crates compiled
struct AgentBuildSteps: Equatable {
    /// Packages cargo compiles for the agent on Linux
    static let crates = 125
    static let ceiling = 0.99

    private(set) var compiled = 0

    mutating func line(_ text: String) {
        if text.contains("Compiling ") { compiled += 1 }
    }

    var fraction: Double {
        min(Double(compiled) / Double(Self.crates), Self.ceiling)
    }
}

/// Moves a run's percentage with each finished build step
@MainActor
final class AgentBuildProgress {
    private var steps = AgentBuildSteps()
    private weak var state: LongOperationState?

    init(state: LongOperationState) {
        self.state = state
    }

    func line(_ text: String) {
        steps.line(text)
        state?.progress = steps.fraction
    }
}
