import SwiftUI

struct RunningProcessButton: View {
    @StateObject private var installs = InstallSessionRegistry.shared
    @StateObject private var operations = RunningOperationsRegistry.shared
    @StateObject private var navigator = AppNavigator.shared

    var body: some View {
        if let deployment = installs.installing.first {
            button { navigator.resumeInstall = deployment }
        } else if let entry = operations.entries.first {
            button { operations.present(entry.state) }
        }
    }

    private func button(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Go to the process", systemImage: "arrow.up.forward.app")
        }
    }
}
