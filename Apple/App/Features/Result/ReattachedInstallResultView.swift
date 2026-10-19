import SwiftUI
import gryonixNexusCore
import MailRecipe
import ServerControl

struct ReattachedInstallResultView: View {
    let deployment: Deployment

    private enum Load {
        case loading
        case ready(bundle: GeneratedBundle, openPorts: [OpenPortRequirement])
        case unavailable
    }

    @State private var load: Load = .loading
    @State private var resumingViewModel: InstallViewModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch load {
            case .loading:
                ProgressView("Rebuilding the setup…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .closeToolbar(dismiss)
            case .ready(let bundle, let openPorts):
                SimpleResultView(bundle: bundle,
                                 deployment: deployment,
                                 openPorts: openPorts,
                                 resumingRunningInstall: true,
                                 resumingViewModel: resumingViewModel)
            case .unavailable:
                ContentUnavailableView {
                    Label("Can't reopen this setup", systemImage: "questionmark.folder")
                } description: {
                    Text("The saved configuration for this server could not be read, so its records and ports can't be shown here. The installation is still running on the server.")
                }
                .closeToolbar(dismiss)
            }
        }
        .task {
            guard case .loading = load else { return }
            if let rebuilt = await ReattachedInstall.rebuild(for: deployment) {
                if #available(macOS 15.0, *) {
                    let viewModel = InstallViewModel(deployment: deployment, bundle: rebuilt.bundle)
                    viewModel.resumeAgentPhase()
                    resumingViewModel = viewModel
                }
                load = .ready(bundle: rebuilt.bundle, openPorts: rebuilt.openPorts)
            } else {
                load = .unavailable
            }
        }
    }
}

private extension View {
    func closeToolbar(_ dismiss: DismissAction) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}
