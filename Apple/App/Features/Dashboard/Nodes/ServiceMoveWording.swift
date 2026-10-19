import AgentControl
import Foundation
import ServerControl

enum ServiceMoveWording {
    static func stepText(_ step: ServiceMoveStep) -> String {
        switch step {
        case .check: return UIL10n.string("Checking both machines…")
        case .install: return UIL10n.string("Installing on the new machine…")
        case .backup: return UIL10n.string("Backing up the old copy…")
        case .stop: return UIL10n.string("Stopping the old copy…")
        case .send: return UIL10n.string("Copying the data…")
        case .restore: return UIL10n.string("Restoring the data on the new machine…")
        case .switchEntry: return UIL10n.string("Pointing the entry server at the new machine…")
        case .verify: return UIL10n.string("Checking that it answers…")
        case .finish: return UIL10n.string("Cleaning up…")
        }
    }

    static func refusal(_ reason: ServiceMoveRefusal, serviceName: String) -> String {
        switch reason {
        case .notMovable:
            return UIL10n.string("%@ cannot be moved to another machine.", serviceName)
        case .noAgent:
            return UIL10n.string("Moving a service needs the server agent on every machine.")
        case .sameMachine, .unknownMachine:
            return UIL10n.string("That machine is not part of this deployment.")
        case .targetDoesNotRunServices:
            return UIL10n.string("That machine does not run services.")
        case .noFront:
            return UIL10n.string("No machine answers on the public address and runs services, so the entry cannot be pointed at another machine.")
        }
    }

    static func problem(_ problem: ServiceMoveProblem, serviceName: String) -> String {
        switch problem {
        case .notOnSource:
            return UIL10n.string("%@ is not installed on the old machine.", serviceName)
        case .alreadyOnTarget:
            return UIL10n.string("%@ is already installed on the new machine. Remove it there first.", serviceName)
        case .noSiteOnFront:
            return UIL10n.string("The entry server has no web page for %@.", serviceName)
        case .frontDisagrees:
            return UIL10n.string("The entry server serves %@ differently from what the app recorded, so nothing was changed.", serviceName)
        case .notAnswering(let status, _):
            return UIL10n.string("The new machine did not answer (status %lld).", Int(status))
        case .noArchive:
            return UIL10n.string("The backup could not be found.")
        case .noLoginAccess:
            return UIL10n.string("The app cannot sign in to the new machine to hand over the data.")
        }
    }

    static func failure(_ failure: ServiceMoveFailure, serviceName: String) -> String {
        var lines = [reason(of: failure.underlying, serviceName: serviceName)]
        let undone = failure.undone
        if failure.step <= .backup {
            lines.append(UIL10n.string("Nothing was changed on the old machine."))
        } else if undone.sourceStarted {
            lines.append(UIL10n.string("The old copy is running again."))
        }
        if undone.entryRestored {
            lines.append(UIL10n.string("The entry server points at the old machine again."))
        }
        if undone.targetCopyRemoved {
            lines.append(UIL10n.string("The copy on the new machine was removed."))
        }
        if !undone.problems.isEmpty {
            lines.append(UIL10n.string("Not everything could be put back: %@", undone.problems.joined(separator: "; ")))
        }
        return lines.joined(separator: "\n")
    }

    static func reason(of error: Error, serviceName: String) -> String {
        if let problem = error as? ServiceMoveProblem {
            return Self.problem(problem, serviceName: serviceName)
        }
        return (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
