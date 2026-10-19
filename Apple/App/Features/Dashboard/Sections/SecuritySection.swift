import AgentControl
import ServerControl
import SwiftUI

/// Panel guard, intrusion defence and SSH access in one section
struct SecuritySection: View {
    @ObservedObject var viewModel: DashboardViewModel
    /// The screen a tapped row opens, pushed by the dashboard
    @Binding var route: SecurityRoute?

    var body: some View {
        Section {
            if viewModel.hasAdminLockdown {
                AdminLockdownRow(viewModel: viewModel, route: $route)
            }
            CrowdSecRow(viewModel: viewModel, route: $route)
            SSHAccessRow(viewModel: viewModel, route: $route)
        } header: {
            header
        } footer: {
            footer
        }
    }

    private var header: some View {
        InfoSectionHeader("Security",
                          isRefreshing: viewModel.isReadingSecuritySection,
                          refresh: { await viewModel.refreshSecuritySection() }) {
            Text("The arrow by this title reads all of this from the server again; each row has its own arrow for just that one.")
            Text("CrowdSec watches this server's login and web logs and automatically blocks the addresses behind repeated attacks — brute-force, scanning, known-bad hosts. It's installed and kept up to date with the server, and enforces a blocklist shared by every CrowdSec install. There's nothing to configure.")
            Text("This server accepts SSH keys only once password login is closed — the app then signs in with the key it keeps on this device. Whether the machine currently accepts passwords is read from the machine itself, and it can be turned back on here.")
        }
        .task { await viewModel.loadSecurityIfStale() }
        .task { await viewModel.loadSSHPasswordAccessIfStale() }
    }

    @ViewBuilder private var footer: some View {
        if !viewModel.hasAdminLockdown, !viewModel.lockdownPages.isEmpty {
            Text("Restricting the admin panels to VPN-only access needs a VPN installed on this server — the guard admits the tunnel's own subnet, so there would be nothing left to admit. Add a VPN protocol to this server and the switch appears here, covering every panel including AdGuard Home's.")
        }
        sshFooter
        if case .some(let status) = viewModel.securityStatus, status.isKnown, !status.isPresent {
            Text("This server's intrusion defence could not be reached — it may not be installed, or the agent may be too old to report it. Install it here, re-run setup, or update the agent.")
        }
    }

    @ViewBuilder private var sshFooter: some View {
        if case .some(let access) = viewModel.sshPasswordAccess, access.isKnown, !access.isClosed {
            openFooter(access)
        }
    }

    /// Why this server still takes passwords
    @ViewBuilder private func openFooter(_ access: SSHPasswordAccess) -> some View {
        if let names = viewModel.openSSHAccountNames {
            Text("This server still accepts SSH passwords for \(names). Accounts are closed one at a time on the SSH access screen, and an account carrying no key of its own needs a key before it can be closed.")
        } else if access.isOutranked {
            Text("The setting that closes password login is on this server and sshd is ignoring it — something earlier in its SSH configuration allows passwords, usually a cloud image's own file in /etc/ssh/sshd_config.d. It has to be removed on the machine.")
        } else if !access.appKeyPresent {
            Text("This server still accepts SSH passwords, which is what automated attacks try. Password login can only be turned off once this app can get in without one — adding the key does that, over the connection the app already has, and switches this server to key sign-in.")
        } else {
            Text("This server still accepts SSH passwords. Turning that off leaves SSH keys as the only way in — this app's key is already on \(viewModel.sshLoginUser), and the setting can be turned back on here.")
        }
    }
}

/// Intrusion defence as one Security row
struct CrowdSecRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var route: SecurityRoute?
    @State private var confirmingStop = false

    var body: some View {
        SecurityRow(title: "Security", systemImage: mark.symbol, tint: mark.tint,
                    status: status,
                    refreshLabel: "Read the intrusion defence again",
                    isRefreshing: viewModel.isReadingSecurity,
                    refresh: { await viewModel.loadSecurity() },
                    open: { route = .crowdSec }) {
            engineSwitch
        }
        .appTourTarget(.serverSecurity)
        .alert("Stop the protection?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) {
                Task { await viewModel.runSecurityAction(.stop) }
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This server stops watching its login and web logs, and the addresses it is blocking are released. Attacks are not blocked until it is started again — which does happen on the next restart of the machine, because the service stays enabled.")
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_CROWDSEC"] != nil
            else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            route = .crowdSec
        }
        #endif
        installButton
    }

    private var installed: HostSecurityStatus? {
        guard let status = viewModel.securityStatus, status.isKnown, status.isPresent else {
            return nil
        }
        return status
    }

    private var status: LocalizedStringKey? {
        guard let answer = viewModel.securityStatus else { return nil }
        if !answer.isKnown { return "Could not read" }
        if !answer.isPresent { return "Not set up" }
        return answer.isHealthy ? nil : "Degraded"
    }

    private var mark: (symbol: String, tint: Color) {
        guard let answer = viewModel.securityStatus else { return ("shield", .secondary) }
        if !answer.isKnown { return ("questionmark.circle", .orange) }
        if !answer.isPresent { return ("shield.slash", .secondary) }
        return answer.isHealthy
            ? ("checkmark.shield.fill", .green)
            : ("exclamationmark.shield.fill", .orange)
    }

    @ViewBuilder private var engineSwitch: some View {
        if let status = installed {
            SecuritySwitch(isOn: status.engineRunning,
                           isEnabled: viewModel.runningSecurityAction == nil) { wanted in
                if wanted {
                    Task { await viewModel.runSecurityAction(.start) }
                } else {
                    confirmingStop = true
                }
            }
        }
    }

    @ViewBuilder private var installButton: some View {
        if let answer = viewModel.securityStatus, answer.isKnown, !answer.isPresent {
            Button {
                Task { await viewModel.runSecurityAction(.install) }
            } label: {
                Label("Install Protection", systemImage: "shield.lefthalf.filled")
            }
            .rowActionButtonStyle()
        }
    }
}

/// SSH password login as one Security row
struct SSHAccessRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var route: SecurityRoute?
    @State private var confirmingClose = false
    @State private var confirmingOpen = false

    var body: some View {
        SecurityRow(title: "SSH access", systemImage: mark.symbol, tint: mark.tint,
                    status: isUnread ? "Could not read" : nil,
                    refreshLabel: "Read SSH access again",
                    isRefreshing: viewModel.isReadingSSHPasswordAccess,
                    refresh: { await viewModel.loadSSHPasswordAccess() },
                    open: { route = .sshAccess }) {
            passwordSwitch
        }
        .alert("Turn off password login?", isPresented: $confirmingClose) {
            Button("Turn Off", role: .destructive) { set(open: false) }
                .dangerTint()
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(verbatim: UIL10n.string("This server will only accept SSH key logins, for every account on it. This app's key is on %@, and it stays — but anyone who signs in with a password will not be able to any more.",
                                         viewModel.sshLoginUser))
        }
        .alert("Allow password login again?", isPresented: $confirmingOpen) {
            Button("Allow", role: .destructive) { set(open: true) }
                .dangerTint()
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Passwords are what automated attacks try, thousands of times a day. Turn this back on only if you need to sign in to this machine without a key.")
        }
        detail
    }

    private var access: SSHPasswordAccess? {
        guard let answer = viewModel.sshPasswordAccess, answer.isKnown else { return nil }
        return answer
    }

    private var isUnread: Bool {
        guard let answer = viewModel.sshPasswordAccess else { return false }
        return !answer.isKnown
    }

    private var mark: (symbol: String, tint: Color) {
        guard let answer = access else {
            return isUnread ? ("questionmark.circle", .orange) : ("lock.shield", .secondary)
        }
        return answer.isClosed ? ("lock.shield.fill", .green) : ("lock.open", .orange)
    }

    /// Closing without the app's own key would lock everyone out
    private func canSwitch(_ answer: SSHPasswordAccess) -> Bool {
        guard !viewModel.isChangingSSHPassword else { return false }
        return answer.isClosed || answer.appKeyPresent
    }

    @ViewBuilder private var passwordSwitch: some View {
        if let answer = access {
            SecuritySwitch(isOn: answer.isClosed, isEnabled: canSwitch(answer)) { wanted in
                if wanted { confirmingClose = true } else { confirmingOpen = true }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let answer = access, !answer.detail.isEmpty {
            Text(verbatim: answer.detail)
                .font(.caption)
                .foregroundStyle(answer.isClosed ? Color.secondary : Color.orange)
        }
    }

    private func set(open: Bool) {
        Task { await viewModel.setSSHPasswordLogin(open: open) }
    }
}
