import AgentControl
import ServiceCatalog
import SwiftUI

/// What the machine lacks for the chosen services
struct HostCompatibilitySection: View {
    let findings: [InstallFinding]

    var body: some View {
        if !findings.isEmpty {
            Section {
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    Label(HostFindingText.text(finding), systemImage: finding.isBlocking
                          ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(finding.isBlocking ? Color.red : Color.orange)
                }
            } header: {
                Text("Checked against this machine")
            } footer: {
                if findings.contains(where: \.isBlocking) {
                    Text("A blocked service cannot be installed on this machine. The others install with what the system allows.")
                }
            }
        }
    }

    static func blocked(_ findings: [InstallFinding]) -> Set<ServiceID> {
        Set(findings.filter(\.isBlocking).map(\.service))
    }
}

/// A finding in the app's own words
enum HostFindingText {
    static func text(_ finding: InstallFinding) -> String {
        let name = ServiceRegistry.service(finding.service)?.displayName ?? finding.service.rawValue
        let args = finding.args
        switch finding.code {
        case "needs_newer_os" where args.count >= 2:
            return UIL10n.string("%1$@ needs %2$@; this machine runs %3$@.", name, args[1], args[0])
        case "package_unavailable" where args.count >= 2:
            return UIL10n.string("%1$@ cannot be installed here: the package %2$@ is not available for %3$@.",
                                 name, args[0], args[1])
        case "reduced_on_older_os" where args.count >= 2:
            return UIL10n.string("%1$@ installs on %2$@ without %3$@, which need newer system libraries.",
                                 name, args[0], args[1])
        case "no_sound_card":
            return finding.isBlocking
                ? UIL10n.string("%@ needs a sound card, and this machine has none.", name)
                : UIL10n.string("%@ installs, but this machine has no sound card, so nothing can play yet.", name)
        default:
            return finding.message
        }
    }
}
