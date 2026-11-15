import Foundation
import ServerControl

/// Each machine's agent build, summed up on one run
@MainActor
final class AgentBuildMachines {
    enum Phase: Equatable {
        case building(since: Date)
        case done
        case failed
    }

    private(set) var names: [String]
    private var phases: [String: Phase] = [:]
    private var steps: [String: AgentBuildSteps] = [:]
    private weak var state: LongOperationState?
    private var ticker: Task<Void, Never>?

    init(state: LongOperationState, names: [String]) {
        self.state = state
        self.names = names
    }

    /// Lines carry the machine's name only when there are several
    var isSeveral: Bool { names.count > 1 }

    func started(_ name: String, at now: Date = Date()) {
        phases[name] = .building(since: now)
        show()
        guard isSeveral, ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.show()
            }
        }
    }

    func finished(_ name: String, ok: Bool) {
        phases[name] = ok ? .done : .failed
        show()
        if !phases.values.contains(where: { if case .building = $0 { return true } else { return false } }) {
            ticker?.cancel()
            ticker = nil
        }
    }

    /// A machine's phase as the card text or a line
    func phase(_ text: String, of name: String) {
        guard isSeveral else {
            state?.progressText = text
            return
        }
        log(text, of: name)
    }

    /// One line of a machine's build
    func output(_ line: String, of name: String) {
        steps[name, default: AgentBuildSteps()].line(line)
        state?.progress = names.map { steps[$0]?.fraction ?? 0 }.reduce(0, +) / Double(max(names.count, 1))
        log(line, of: name)
    }

    private func log(_ line: String, of name: String) {
        guard let state else { return }
        let clean = ANSIStripper.strip(line)
        let shown = isSeveral ? "\(name): \(clean)" : clean
        state.log = OutputTail.tail(state.log + shown + "\n", maxCharacters: OutputTail.logCharacters)
    }

    private func show() {
        guard isSeveral else { return }
        state?.progressText = summary()
    }

    /// Each machine's state, in the given order
    func summary(now: Date = Date()) -> String {
        names.map { name in
            switch phases[name] {
            case .done: return UIL10n.string("%@: done", name)
            case .failed: return UIL10n.string("%@: failed", name)
            case .building(let since):
                let minutes = Int(now.timeIntervalSince(since) / 60)
                return minutes < 1 ? UIL10n.string("%@: building", name)
                    : UIL10n.string("%1$@: building, %2$lld min", name, minutes)
            case nil: return UIL10n.string("%@: waiting", name)
            }
        }.joined(separator: " · ")
    }
}
