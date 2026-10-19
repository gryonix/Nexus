import AgentClient
import SwiftUI

/// The server events a person can switch on or off
struct NotifyEventToggles: View {
    @Binding var disks: Bool
    @Binding var spacePercent: Int
    @Binding var services: Bool
    @Binding var backups: Bool
    @Binding var agentUpdate: Bool
    @Binding var operations: Bool
    @Binding var sshLogins: Bool

    var body: some View {
        Toggle("Disks and RAID", isOn: $disks)
        if disks {
            Stepper(value: $spacePercent, in: 50...99, step: 5) {
                Text(verbatim: UIL10n.string("Warn when a disk is %lld%% full", spacePercent))
            }
        }
        Toggle("A service stopped or keeps restarting", isOn: $services)
        Toggle("A backup failed", isOn: $backups)
        Toggle("A new agent version", isOn: $agentUpdate)
        Toggle("A long operation finished", isOn: $operations)
        Toggle("Someone signed in over SSH", isOn: $sshLogins)
    }
}

extension NotifyEventToggles {
    /// Toggles that edit one server's checks
    init(checks: Binding<Gryonixnexusd_V1_NotifyChecks>) {
        func flag(_ path: WritableKeyPath<Gryonixnexusd_V1_NotifyChecks, Bool>) -> Binding<Bool> {
            Binding(get: { checks.wrappedValue[keyPath: path] }, set: { checks.wrappedValue[keyPath: path] = $0 })
        }
        let disks = Binding(get: { checks.wrappedValue.raid || checks.wrappedValue.diskSpace },
                            set: { on in
                                checks.wrappedValue.raid = on
                                checks.wrappedValue.smart = on
                                checks.wrappedValue.diskSpace = on
                            })
        let percent = Binding(get: { (50...99).contains(Int(checks.wrappedValue.diskSpacePercent)) ? Int(checks.wrappedValue.diskSpacePercent) : 90 },
                              set: { checks.wrappedValue.diskSpacePercent = UInt32($0) })
        self.init(disks: disks, spacePercent: percent, services: flag(\.services), backups: flag(\.backups),
                  agentUpdate: flag(\.agentUpdate), operations: flag(\.operations), sshLogins: flag(\.sshLogins))
    }
}
