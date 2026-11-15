import AgentClient
import SwiftUI

/// What a person can do about an agent's refusal
enum RefusalSolution {
    /// Advice for the refusal behind this error text
    static func advice(for text: String) -> String? {
        guard let refusal = AgentRefusals.shared.find(in: text) else { return nil }
        switch refusal.reason {
        case "install.machine_not_at_home":
            return UIL10n.string("If this machine stands in your home, add the service again and turn on “%@”. On a rented server this service cannot work.", UIL10n.string("This machine stands in my home"))
        case "install.incompatible":
            return UIL10n.string("This machine's system is too old or lacks a part the service needs. Update the system to a newer release, or install the service on another machine.")
        case "install.hub_has_player":
            return UIL10n.string("Remove %@ from this machine first, then install the audio hub — it brings the same player.", refusal.args.first ?? "")
        case "install.player_in_hub":
            return UIL10n.string("The audio hub on this machine already plays this. Use it from the hub, or remove the hub first.")
        case "install.needs_home_assistant":
            return UIL10n.string("Install Home Assistant on this machine first, then add this service.")
        case "install.no_reverse_proxy":
            return UIL10n.string("Install Caddy on this server first, then add this service.")
        case "install.zigbee_no_stick", "install.stick_missing":
            return UIL10n.string("Plug the Zigbee stick into this machine and check its path in the service settings, then install again.")
        case "install.site_name_taken":
            return UIL10n.string("This site name is already used on this server. Choose another name for the service.")
        case "install.already_running":
            return UIL10n.string("This service is already being installed on this server. Wait until that run ends.")
        case "install.ports_in_use":
            return UIL10n.string("Another program on this machine holds the ports this service needs. Stop or remove it, then install again.")
        case "install.docker_unavailable", "host.docker_unavailable":
            return UIL10n.string("Docker does not answer on this machine. Use “%@” on this server, then install again.", UIL10n.string("Repair server"))
        default:
            return adviceOutsideInstall(refusal)
        }
    }

    /// Advice for refusals of a running server
    private static func adviceOutsideInstall(_ refusal: AgentRefusal) -> String? {
        let installFirst = { (name: String) in UIL10n.string("Install %@ on this server first, then try again.", name) }
        switch refusal.reason {
        case "security.not_installed": return installFirst("CrowdSec")
        case "mesh.not_installed": return installFirst("Headscale")
        case "models.no_engine": return installFirst("Ollama")
        case "audio.hub_not_installed": return installFirst("Audio hub (odio)")
        case "host.needs_repair":
            return UIL10n.string("This server's tools are missing or outdated. Use “%@” on this server, then try again.", UIL10n.string("Repair server"))
        case "vpn.no_panel", "vpn.protocol_not_installed":
            return UIL10n.string("Install a VPN protocol on this server first, then try again.")
        case "vpn.panel_not_running", "vpn.login_refused":
            return UIL10n.string("The VPN panel on this server does not answer. Install the VPN protocol again to bring it back.")
        case "jobs.cannot_stop":
            return UIL10n.string("This run cannot be interrupted. Wait until it ends.")
        case "containers.backup_required":
            return UIL10n.string("This group has a database. Update it with the backup turned on.")
        case "containers.nothing_to_archive":
            return UIL10n.string("This group keeps no data outside its images. Update it without a backup.")
        case "sites.caddy_refused":
            return UIL10n.string("Caddy did not accept the change and keeps its previous settings. Check that Caddy is running on this server, then try again.")
        case "audio.hub_not_answering":
            return UIL10n.string("The audio hub does not answer. Restart the machine, or install the audio hub again.")
        case "firewall.rules_refused":
            return UIL10n.string("The firewall did not take the rule. Use “%@” on this server, then try again.", UIL10n.string("Repair server"))
        case "move.no_space":
            return UIL10n.string("The machine this service moves to has too little free space for its data. Free up space there, then start the move again.")
        case "backup.unreadable":
            return UIL10n.string("The backup folder cannot be read. Check that the backup drive is connected, then try again.")
        case "security.ssh_unchanged":
            return UIL10n.string("The SSH settings were not changed. Check that the server accepts this device's key, then try again.")
        default:
            return nil
        }
    }
}

/// The advice under a failed run, when there is one
struct RefusalAdviceView: View {
    let errorText: String?

    var body: some View {
        if let errorText, let advice = RefusalSolution.advice(for: errorText) {
            VStack(alignment: .leading, spacing: 4) {
                Label("What to do", systemImage: "lightbulb")
                    .font(.callout.weight(.semibold))
                Text(verbatim: advice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A refusal with its advice, over the screen
struct RefusalSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: message).textSelection(.enabled)
                }
                Section {
                    RefusalAdviceView(errorText: message)
                }
            }
            .formStyle(.grouped)
            .screenTitle("Error")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}
