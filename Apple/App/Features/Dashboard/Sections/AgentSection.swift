import ServerControl
import SwiftUI

struct AgentSection: View {
    let version: String?
    let usesAgent: Bool
    /// The install/update command, already carrying this server's address
    let command: String
    let onCopy: () -> Void
    var onInstall: () -> Void = {}
    /// Asks the SERVER whether the agent is there, right now
    var onCheck: () -> Void = {}
    var isChecking: Bool = false
    var checkResult: CheckResult?

    enum CheckResult: Equatable {
        case installed(version: String)
        case installedUnknownVersion
        case unreachable(String)
    }
    var showsRelay: Bool = false
    var onConfigureRelay: () -> Void = {}
    var showsDynamicDNS: Bool = false
    var dynamicDNSIsOn: Bool = false
    var onDynamicDNS: () -> Void = {}
    var showsNotifications: Bool = false
    var onNotifications: () -> Void = {}
    /// Removes the agent, keeping services and settings
    var onRemove: (() -> Void)?
    /// Builds the agent again from scratch, keeping its settings
    var onReinstall: (() -> Void)?
    /// The machines this deployment is made of
    var nodesDestination: AnyView?

    @AppStorage("agent.source") private var sourceChoice = AgentSource.app.rawValue
    @State private var confirmingRemoval = false
    @State private var confirmingReinstall = false

    /// Where the agent sources come from
    @ViewBuilder private var sourceRow: some View {
        WrappingPicker("Sources", selection: Binding(
            get: { AgentSource.named(sourceChoice) },
            set: { sourceChoice = $0.rawValue }
        )) {
            Text("From this app").tag(AgentSource.app)
            Text("Repository — main").tag(AgentSource.repositoryMain)
            Text("Repository — beta").tag(AgentSource.repositoryBeta)
            Text("Repository — wip").tag(AgentSource.repositoryWip)
        }
        .infoNote("Agent sources") { agentSourcesNote }
    }

    /// The intro, then every source compared row by row
    @ViewBuilder private var agentSourcesNote: some View {
        Text("The app carries the agent it was released with, so a newer agent waits for the store's review. The public repository does not wait: `main` is the released line and `beta` is the one being tried out. The server fetches the branch itself and builds it — the app never gets between them.")
        ForEach(AgentSource.allCases) { source in
            VStack(alignment: .leading, spacing: 6) {
                Text(source.title).font(.headline)
                Text(source.summary).foregroundStyle(.secondary)
                ForEach(source.comparisonRows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(row.value).multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                }
            }
            if source != AgentSource.allCases.last {
                Divider()
            }
        }
    }

    var body: some View {
        Section {
            if usesAgent {
                LabeledContent("Agent") {
                    if let version, !version.isEmpty {
                        Text(verbatim: version).foregroundStyle(.secondary)
                    } else {
                        Text("Installed").foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("The agent is not installed on this server.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            sourceRow
            CompactActionGroup([
                CompactAction(isChecking ? "Checking…" : "Check the agent",
                              systemImage: "stethoscope") {
                    onCheck()
                },
                CompactAction(usesAgent ? "Update the agent" : "Install the agent",
                              systemImage: "arrow.down.circle") {
                    onInstall()
                },
                CompactAction(usesAgent ? "Copy the update command" : "Copy the install command",
                              systemImage: "doc.on.doc") {
                    onCopy()
                }
            ])
            .disabled(isChecking)
            .listRowSeparator(.hidden)
            .padding(.vertical, 2)
            checkResultRows
            extraRows
            if usesAgent, onReinstall != nil {
                reinstallRow
            }
            if usesAgent, onRemove != nil {
                removalRow
            }
        } header: {
            InfoSectionHeader("Agent") {
                Text(usesAgent
                     ? "Updating rebuilds it on the server from the sources this app carries. Removing it keeps the services, their data and its settings; the app then manages the server over SSH."
                     : "The app sends the agent's sources to the server and builds it there, in a throwaway container. The first build takes a few minutes. The command below does the same thing by hand.")
                if showsRelay {
                    Text("The relay forwards this deployment's ports into the tunnel. Configure it after installing or removing services, so its firewall matches what the local server now runs.")
                }
                if showsDynamicDNS {
                    Text("On a connection whose address changes, the server updates its own DNS records on a timer — it keeps working while this app is closed.")
                }
            }
        }
    }

    @ViewBuilder
    private var extraRows: some View {
        if showsRelay {
            Button {
                onConfigureRelay()
            } label: {
                Label("Configure the relay", systemImage: "arrow.left.arrow.right")
            }
        }
        if let nodesDestination {
            NavigationLink {
                nodesDestination
            } label: {
                Label("Servers", systemImage: "server.rack")
            }
        }
        if showsDynamicDNS {
            Button {
                onDynamicDNS()
            } label: {
                LabeledContent {
                    Text(dynamicDNSIsOn ? "On" : "Off").foregroundStyle(.secondary)
                } label: {
                    Label("Dynamic DNS", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        if showsNotifications {
            Button {
                onNotifications()
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
        }
    }

    private var reinstallRow: some View {
        Button {
            confirmingReinstall = true
        } label: {
            Label("Reinstall the agent", systemImage: "arrow.clockwise.circle")
        }
        .disabled(isChecking)
        .alert("Reinstall the agent?", isPresented: $confirmingReinstall) {
            Button("Reinstall") { onReinstall?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every machine of this server builds the agent again from scratch and restarts it, even if the version is the same. Its settings, passwords and paired devices stay; services keep running.")
        }
    }

    private var removalRow: some View {
        Button(role: .destructive) {
            confirmingRemoval = true
        } label: {
            Label("Remove the agent", systemImage: "trash")
        }
        .dangerTint()
        .alert("Remove the agent from this server?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { onRemove?() }
                .dangerTint()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Services, their data and the agent's settings stay. Installing the agent again picks them up.")
        }
    }

    @ViewBuilder
    private var checkResultRows: some View {
        if let checkResult {
            switch checkResult {
            case .installed(let version):
                Label {
                    Text(verbatim: UIL10n.string("The server answers. Agent %@.", version))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.footnote)
            case .installedUnknownVersion:
                Label {
                    Text("The server answers, but does not report a version.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.footnote)
            case .unreachable(let reason):
                Label {
                    Text(verbatim: reason)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.footnote)
            }
        }
    }
}
