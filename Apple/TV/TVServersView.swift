import ServerControl
import SwiftUI

struct TVServersView: View {
    @StateObject private var viewModel = ServerListViewModel()
    @StateObject private var metrics = ServerMetricsStore()
    @State private var path = NavigationPath()
    @State private var pendingDelete: Deployment?
    @State private var addingFromPhone = false
    @Environment(\.scenePhase) private var scenePhase

    private let columns = [GridItem(.adaptive(minimum: 520, maximum: 900), spacing: 48, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(viewModel.deployments) { deployment in
                        card(deployment)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)
                .padding(.bottom, 60)
                addFromPhoneButton
            }
            .overlay { if viewModel.deployments.isEmpty { TVNoServers(onAdd: { addingFromPhone = true }) } }
            .navigationDestination(for: Deployment.self) { deployment in
                DashboardView(deployment: deployment, onUpdate: { viewModel.upsert($0) },
                              onDelete: { viewModel.delete($0) })
            }
            .navigationDestination(for: MetricsHistoryTarget.self) { ServerPageDestination(value: $0) }
            .navigationDestination(for: EnergyTarget.self) { ServerPageDestination(value: $0) }
            .navigationDestination(for: StorageTarget.self) { ServerPageDestination(value: $0) }
            .navigationDestination(for: SpeedTestTarget.self) { ServerPageDestination(value: $0) }
            .navigationDestination(for: TopProcessesTarget.self) { ServerPageDestination(value: $0) }
        }
        .confirmationDialog("Delete from this Apple TV?", isPresented: $pendingDelete.isPresent(),
                            presenting: pendingDelete) { deployment in
            Button("Delete", role: .destructive) { viewModel.delete(deployment) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The server stays on your other devices and in iCloud. Nothing changes on the server.")
        }
        .sheet(isPresented: $addingFromPhone) { TVAddFromPhoneSheet() }
        .task {
            viewModel.load()
            #if DEBUG
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_TV_OPEN_SERVER"]?.isEmpty == false,
               let first = viewModel.deployments.first {
                path.append(first)
            }
            #endif
        }
        .onAppear { metrics.sync(with: viewModel.deployments) }
        .onChange(of: viewModel.deployments) { _, deployments in metrics.sync(with: deployments) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { metrics.stopAll() } else { metrics.sync(with: viewModel.deployments) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncChangedServers)) { _ in viewModel.load() }
    }

    private func card(_ deployment: Deployment) -> some View {
        Button {
            if LicensePrompt.shared.allow(deployment) { path.append(deployment) }
        } label: {
            ServerCardRow(deployment: deployment, metrics: metrics.card(for: deployment.id))
                .padding(8)
        }
        .buttonStyle(.plain)
        .contextMenu { cardMenu(deployment) }
    }

    /// Everything the phone's card menu offers that works without typing
    @ViewBuilder
    private func cardMenu(_ deployment: Deployment) -> some View {
        let index = viewModel.deployments.firstIndex(of: deployment)
        Menu {
            ServerAppearanceChoices(deployment: { current(deployment) },
                                    setCardSize: { size in restyle(deployment) { $0.cardSize = size } },
                                    setIndicatorStyle: { style in restyle(deployment) { $0.metricsIndicatorStyle = style } },
                                    setTint: { tint in restyle(deployment) { $0.tintName = tint } })
        } label: {
            Label("Appearance", systemImage: "paintbrush")
        }
        Button { move(deployment, by: -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
            .disabled(index == nil || index == 0)
        Button { move(deployment, by: 1) } label: { Label("Move later", systemImage: "arrow.right") }
            .disabled(index == nil || index == viewModel.deployments.count - 1)
        Button(role: .destructive) {
            pendingDelete = deployment
        } label: {
            Label("Delete from this Apple TV", systemImage: "trash")
        }
    }

    private func current(_ deployment: Deployment) -> Deployment {
        viewModel.deployments.first { $0.id == deployment.id } ?? deployment
    }

    private func restyle(_ deployment: Deployment, _ change: (inout Deployment) -> Void) {
        var updated = current(deployment)
        change(&updated)
        withAnimation(.snappy(duration: 0.3)) { viewModel.updateAppearance(updated) }
    }

    /// Moves a server one place and saves the order
    private func move(_ deployment: Deployment, by offset: Int) {
        guard let from = viewModel.deployments.firstIndex(where: { $0.id == deployment.id }) else { return }
        let to = from + offset
        guard viewModel.deployments.indices.contains(to) else { return }
        withAnimation(.snappy(duration: 0.3)) {
            viewModel.move(fromOffsets: IndexSet(integer: from), toOffset: offset > 0 ? to + 1 : to)
        }
    }

    private var addFromPhoneButton: some View {
        Button {
            addingFromPhone = true
        } label: {
            Label("Add from iPhone", systemImage: "iphone.and.arrow.forward")
        }
        .padding(.bottom, 60)
    }
}

private struct TVNoServers: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack").font(.system(size: 80)).foregroundStyle(.secondary)
            Text("No servers yet").font(.title2.weight(.semibold))
            Text("Servers arrive through iCloud from your other devices, or from Nexus on your iPhone: Settings › Apple TV › Send servers.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 900)
            Button("Add from iPhone", action: onAdd)
        }
    }
}
