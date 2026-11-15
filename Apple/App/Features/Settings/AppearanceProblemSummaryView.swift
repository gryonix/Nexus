import ServerControl
import SwiftUI

/// Appearance → Problem summary: the tiles above the servers
struct AppearanceProblemSummaryView: View {
    @AppStorage(ServerProblemCards.shownKey) private var shown = true
    @AppStorage(ServerProblemCards.hiddenKey) private var hiddenRaw = ""

    var body: some View {
        Form {
            Section {
                Toggle("Show problem summary", isOn: $shown)
            } footer: {
                Text("Tiles above the servers that count unreachable machines, full disks, stopped services and pending updates in the chosen group.")
            }
            if shown {
                Section("Tiles") {
                    ForEach(ServerProblem.allCases, id: \.self) { problem in
                        Toggle(ServerProblemCards.title(problem), isOn: binding(problem))
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .screenTitle("Problem summary")
        .raisedNavigationTitle()
    }

    private func binding(_ problem: ServerProblem) -> Binding<Bool> {
        Binding {
            ServerProblemCards.visible(hiddenRaw: hiddenRaw).contains(problem)
        } set: { on in
            hiddenRaw = ServerProblemCards.hiddenRaw(hiddenRaw, problem: problem, shown: on)
        }
    }

    /// The value shown on the Appearance row
    static func summary(shown: Bool, hiddenRaw: String) -> String {
        guard shown else { return UIL10n.string("Off") }
        let count = ServerProblemCards.visible(hiddenRaw: hiddenRaw).count
        return "\(count)/\(ServerProblem.allCases.count)"
    }
}
