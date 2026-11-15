import ServerControl
import ServiceCatalog
import SwiftUI

/// Counts of servers by problem; a tap filters the list
struct ServerProblemCards: View {
    let counts: [ServerProblem: Int]
    @Binding var selection: ServerProblem?
    var explain: ((ServerProblem) -> Void)?
    @ObservedObject private var modules = ModuleSettings.shared
    @AppStorage(Self.shownKey) private var shown = true
    @AppStorage(Self.hiddenKey) private var hiddenRaw = ""

    static let shownKey = "servers.problemSummary"
    static let hiddenKey = "servers.problemSummary.hidden"

    /// Tiles switched on, in enum order
    static func visible(hiddenRaw: String) -> [ServerProblem] {
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        return ServerProblem.allCases.filter { !hidden.contains($0.rawValue) }
    }

    /// The stored value with one tile switched
    static func hiddenRaw(_ raw: String, problem: ServerProblem, shown: Bool) -> String {
        var hidden = Set(raw.split(separator: ",").map(String.init))
        if shown { hidden.remove(problem.rawValue) } else { hidden.insert(problem.rawValue) }
        return ServerProblem.allCases.map(\.rawValue).filter(hidden.contains).joined(separator: ",")
    }

    var body: some View {
        let tiles = Self.visible(hiddenRaw: hiddenRaw)
        if shown, !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(tiles, id: \.self) { problem in
                        card(problem)
                    }
                }
                if modules.isOn(.ai), let explain, let selection {
                    Button { explain(selection) } label: {
                        Label("Explain", systemImage: "sparkles")
                    }
                    .secondaryActionButtonStyle()
                }
            }
        }
    }

    private func card(_ problem: ServerProblem) -> some View {
        let count = counts[problem] ?? 0
        let chosen = selection == problem
        return Button {
            selection = chosen ? nil : problem
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(count)").font(.title2.weight(.semibold))
                Text(Self.title(problem)).font(.caption)
                    .lineLimit(Self.isOneWord(problem) ? 1 : 2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(chosen ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(count > 0 ? Self.tint(problem) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !chosen)
    }

    /// One word shrinks instead of breaking mid-word
    private static func isOneWord(_ problem: ServerProblem) -> Bool {
        !UIL10n.string(titleKey(problem)).contains(" ")
    }

    static func title(_ problem: ServerProblem) -> LocalizedStringKey {
        LocalizedStringKey(titleKey(problem))
    }

    static func titleKey(_ problem: ServerProblem) -> String {
        switch problem {
        case .unreachable: return "Unreachable"
        case .diskAlmostFull: return "Disk almost full"
        case .serviceDown: return "Service down"
        case .updatesPending: return "Updates pending"
        }
    }

    private static func tint(_ problem: ServerProblem) -> Color {
        switch problem {
        case .unreachable, .serviceDown: return .red
        case .diskAlmostFull: return .orange
        case .updatesPending: return .blue
        }
    }
}
