#if DEBUG
import Foundation
import gryonixNexusCore
import os
import ServerControl
import ServiceCatalog
import SwiftUI

enum InstallResetProbe {
    static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "installreset")

    static func note(_ what: String, trace: Bool = false) {
        if trace {
            let frames = Thread.callStackSymbols.prefix(6).joined(separator: " <- ")
            log.error("RESET-PROBE \(what, privacy: .public)  [\(frames, privacy: .public)]")
        } else {
            log.error("RESET-PROBE \(what, privacy: .public)")
        }
    }

    static var autoDrive: Bool {
        let mode = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_INSTALL_RESET"]
        return mode == "1" || mode == "setup"
    }

    /// Drives to the install screen and stops before installing
    static var stopsAtSetup: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_INSTALL_RESET"] == "setup"
    }

    @MainActor
    static func forgetFleetIfAsked() {
        guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_FORGET_FLEET"] == "1" else {
            return
        }
        let store = FileDeploymentStore()
        do {
            let stored = try store.load()
            for deployment in stored {
                try? DeploymentEraser.removeEntry(deployment, store: store)
            }
            note("forgetFleetIfAsked: dropped \(stored.count) stored server(s)")
        } catch {
            note("forgetFleetIfAsked: could not read the store — \(error)")
        }
    }

    @MainActor
    static func seedReattachedInstall() async {
        let viewModel = ServiceConfigViewModel(topology: .singleHost, initialScope: .localOnly)
        viewModel.scope = .localOnly
        viewModel.includeDashboardAccess = true
        viewModel.dashboardSSHUser = "control"
        viewModel.publicIP = "192.168.1.77"
        viewModel.domain = "192.168.1.77"
        viewModel.extraServices = [.adguardHome]
        await viewModel.generate()   // persists: saves the deployment + its draft
        guard let deployment = viewModel.savedDeployment else {
            note("seedReattachedInstall: generate() produced no deployment — "
                 + "error=\(viewModel.errorMessage ?? "none")")
            return
        }
        let state = LongOperationState(title: "Installing AdGuard Home",
                                      progressText: "Reattaching…")
        state.reattachDeployment = deployment
        RunningOperationsRegistry.shared.adopt(state, serverName: deployment.name)
        note("seedReattachedInstall: strip row adopted for \(deployment.name)")
    }
}

/// The auto-drive's push from `SimpleResultView` into `InstallFlowView`
struct InstallResetAutoPush: ViewModifier {
    @Binding var isPresented: Bool
    let deployment: Deployment?
    let bundle: GeneratedBundle

    func body(content: Content) -> some View {
        if InstallResetProbe.autoDrive, let deployment {
            content
                .navigationDestination(isPresented: $isPresented) {
                    InstallFlowView(deployment: deployment, bundle: bundle)
                }
                .task {
                    guard !isPresented else { return }
                    InstallResetProbe.note("auto-drive: SimpleResultView appeared, pushing InstallFlowView")
                    isPresented = true
                }
        } else {
            content
        }
    }
}
#endif
