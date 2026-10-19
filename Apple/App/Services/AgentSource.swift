import Foundation
import MailRecipe
import ServerControl
import SwiftUI

/// One parameter this source is compared by
struct AgentSourceComparisonRow: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: LocalizedStringKey
}

/// Where the agent sources come from
enum AgentSource: String, CaseIterable, Identifiable, Sendable {
    case app
    case repositoryMain
    case repositoryBeta

    var id: String { rawValue }

    /// This source's own row title
    var title: LocalizedStringKey {
        switch self {
        case .app: return "From this app"
        case .repositoryMain: return "Repository — main"
        case .repositoryBeta: return "Repository — beta"
        }
    }

    /// What specifically this one source is
    var summary: LocalizedStringKey {
        switch self {
        case .app: return "The exact agent this app was released with."
        case .repositoryMain: return "The public repository's released line, fetched and built by the server itself."
        case .repositoryBeta: return "The public repository's line being tried out, fetched and built by the server itself."
        }
    }

    /// This source compared against the others, one row per parameter
    var comparisonRows: [AgentSourceComparisonRow] {
        switch self {
        case .app:
            return [
                AgentSourceComparisonRow(id: "updates", label: "Updates", value: "Only with an app update"),
                AgentSourceComparisonRow(id: "maturity", label: "Maturity",
                                        value: "Reviewed by the store"),
                AgentSourceComparisonRow(id: "needs", label: "Needs", value: "Nothing else"),
            ]
        case .repositoryMain:
            return [
                AgentSourceComparisonRow(id: "updates", label: "Updates",
                                        value: "As soon as `main` changes"),
                AgentSourceComparisonRow(id: "maturity", label: "Maturity", value: "The released line"),
                AgentSourceComparisonRow(id: "needs", label: "Needs",
                                        value: "The server can reach github.com"),
            ]
        case .repositoryBeta:
            return [
                AgentSourceComparisonRow(id: "updates", label: "Updates",
                                        value: "As soon as `beta` changes"),
                AgentSourceComparisonRow(id: "maturity", label: "Maturity", value: "Being tried out — may break"),
                AgentSourceComparisonRow(id: "needs", label: "Needs",
                                        value: "The server can reach github.com"),
            ]
        }
    }

    /// The branch this reads
    var branch: String? {
        switch self {
        case .app: return nil
        case .repositoryMain: return "main"
        case .repositoryBeta: return "beta"
        }
    }

    /// The version this source carries, where known
    var version: String? {
        self == .app ? AgentBootstrapSections.bundledVersion : nil
    }

    /// The public repository the two branches are read from
    static let repository = "gryonix/nexus-agent"

    /// Only these two names ever reach a shell command
    static func named(_ raw: String) -> AgentSource {
        AgentSource(rawValue: raw) ?? .app
    }

    /// Fetches the branch where the wrapper looks
    func fetchScript(archivePath: String) -> String? {
        guard let branch else { return nil }
        let url = "https://codeload.github.com/\(Self.repository)/tar.gz/refs/heads/\(branch)"
        return """
        set -eu
        WORK="$(mktemp -d)"
        trap 'rm -rf "$WORK"' EXIT
        command -v curl >/dev/null 2>&1 || { echo 'this server has no curl' >&2; exit 1; }
        # The status code, because GitHub hides a private repository behind 404.
        CODE="$(curl -sSL -o "$WORK/repo.tar.gz" -w '%{http_code}' '\(url)' || echo 000)"
        case "$CODE" in
          200) ;;
          404) echo 'github.com/\(Self.repository) answered 404 for the branch \(branch): this server reads it without credentials, so it has to be a public repository and the branch has to exist. Make the repository public, or install the agent from the app.' >&2; exit 1 ;;
          000) echo 'this server could not reach github.com at all' >&2; exit 1 ;;
          *) echo "github.com/\(Self.repository) answered $CODE for the branch \(branch)" >&2; exit 1 ;;
        esac
        mkdir -p "$WORK/repo"
        tar -xzf "$WORK/repo.tar.gz" -C "$WORK/repo"
        ROOT="$(find "$WORK/repo" -mindepth 1 -maxdepth 1 -type d | head -1)"
        [ -d "$ROOT/Agent/gryonixnexusd" ] || { echo 'that branch carries no agent sources' >&2; exit 1; }
        rm -rf "$ROOT/Agent/gryonixnexusd/target"
        tar -czf \(ShellQuoting.singleQuoted(archivePath)) -C "$ROOT" Agent
        grep -m1 '^version' "$ROOT/Agent/gryonixnexusd/Cargo.toml" || true
        """
    }
}
