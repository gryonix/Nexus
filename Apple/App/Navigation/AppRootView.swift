import gryonixNexusCore
import ServerControl
import ServiceCatalog
import SwiftUI

/// Root navigation: scenario selection → step-by-step setup → result
struct AppRootView: View {
    @StateObject private var navigator = AppNavigator.shared
    /// Bumped to rebuild the stack at its root
    @State private var stackID = UUID()
    /// The open setup, if any
    @State private var path: [ScenarioOption] = []

    private func open(scenario id: String) {
        navigator.configuratorScenarioID = nil
        path = ScenarioOption.all.first { $0.id == id }.map { [$0] } ?? []
    }

    private func resetStack() {
        path = []
        stackID = UUID()
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_DKIM"] != nil {
                    InstallFlowView(deployment: .debugDKIMDemo, bundle: GeneratedBundle(artifacts: []))
                } else if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_RESULT_PUSH"] != nil {
                    DebugResultPushRoot()
                } else if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_STORAGE"] != nil,
                          let demo = DemoDeployments.fromEnvironment()?.first {
                    DebugStorageRoot(deployment: demo)
                } else if let mode = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_LOCALONLY"] {
                    localOnlyDebugRoot(mode)
                } else {
                    normalRoot
                }
                #else
                normalRoot
                #endif
            }
            .sectionToolbar(.configurator)
            .navigationDestination(for: ScenarioOption.self) { option in
                SimpleWizardView(topology: option.topology, scope: option.scope,
                                 onLeave: { if !path.isEmpty { path.removeLast() } })
            }
            #if os(iOS) || os(tvOS)
            .onReceive(navigator.$configuratorScenarioID.compactMap { $0 }) { open(scenario: $0) }
            .task { if let id = navigator.configuratorScenarioID { open(scenario: id) } }
            #endif
        }
        .id(stackID)
        .onReceive(navigator.$openServerID.compactMap { $0 }) { id in
            #if DEBUG
            InstallResetProbe.note("AppRootView stackID bump — openServerID=\(id)", trace: true)
            #endif
            resetStack()
        }
        .onReceive(navigator.$configuratorResetToken.dropFirst()) { _ in
            #if DEBUG
            InstallResetProbe.note("AppRootView stackID bump — configuratorResetToken", trace: true)
            #endif
            resetStack()
        }
        #if os(iOS) || os(tvOS)
        .popToRootOnReselect(.configurator) { resetStack() }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func localOnlyDebugRoot(_ mode: String) -> some View {
        SimpleWizardView(topology: .singleHost,
                         scope: mode.hasSuffix("public") ? .publicInternet : .localOnly)
    }
    #endif

    @ViewBuilder
    private var normalRoot: some View {
        Group {
            SimpleConfiguratorView()
        }
    }
}

#if DEBUG
extension Deployment {
    /// Stable across body evaluations: the session registry keys by id
    static let debugDKIMDemo = Deployment(
        name: "dkim-debug", topology: .singleHost, domain: "example.com",
        entry: HostEndpoint(host: "127.0.0.1", user: "root"),
        services: [.mailcow])
}
#endif

#Preview {
    AppRootView()
}

#if DEBUG
private struct DebugStorageRoot: View {
    let deployment: Deployment

    var body: some View {
        StorageView(target: StorageTarget(deployment: deployment,
                                          host: deployment.workerHosts.first ?? deployment.nodes[0].sshHost))
    }
}

/// Pushes the result screen, which pushes the install screen
private struct DebugResultPushRoot: View {
    @State private var showsResult = false

    var body: some View {
        Text(verbatim: "debug root")
            .navigationDestination(isPresented: $showsResult) {
                SimpleResultView(bundle: GeneratedBundle(artifacts: []), deployment: .debugDKIMDemo)
            }
            .task { showsResult = true }
    }
}
#endif
