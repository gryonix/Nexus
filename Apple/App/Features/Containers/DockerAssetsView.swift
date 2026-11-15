import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

enum DockerTab: String, CaseIterable, Identifiable {
    case containers = "Containers"
    case images = "Images"
    case volumes = "Volumes"
    case networks = "Networks"
    case system = "System"

    var id: String { rawValue }
}

/// Picks among the containers area's tabs
struct DockerTabPicker: View {
    @Binding var tab: DockerTab
    let server: String
    @ObservedObject private var modules = ModuleSettings.shared

    private var tabs: [DockerTab] {
        DockerTab.allCases.filter { ![.networks, .system].contains($0) || modules.isOn(.dockerAdvanced, server: server) }
    }

    var body: some View {
        Picker("View", selection: $tab) {
            ForEach(tabs) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Images, volumes or disk use of one server
@available(macOS 15.0, *)
struct DockerAssetsRows: View {
    let tab: DockerTab
    @StateObject private var model: DockerAssetsViewModel
    @State private var confirmPrune = false
    @State private var imageToRemove: DockerImageSummary?
    @State private var volumeToRemove: DockerVolumeSummary?
    @State private var networkToRemove: DockerNetworkSummary?

    init(deployment: Deployment, tab: DockerTab) {
        self.tab = tab
        _model = StateObject(wrappedValue: DockerAssetsViewModel(deployment: deployment))
    }

    var body: some View {
        Group {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
            }
            switch tab {
            case .images: imageRows
            case .volumes: volumeRows
            case .networks: DockerNetworkRows(networks: model.networks, isLoading: model.isLoading) { networkToRemove = $0 }
            default: systemRows
            }
            if tab != .containers && tab != .networks && model.hasUnused {
                Button(role: .destructive) { confirmPrune = true } label: {
                    Label("Remove all unused", systemImage: "trash")
                }
                .dangerTint()
                .disabled(model.isWorking)
            }
        }
        .task { await model.load() }
        .overlay { if model.isLoading && model.images.isEmpty && model.volumes.isEmpty { ProgressView() } }
        .alert("Remove all unused?", isPresented: $confirmPrune) {
            Button("Remove", role: .destructive) { Task { await model.pruneUnused() } }
            .dangerTint()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unused images and volumes are deleted from the server, \(Text(Int64(model.reclaimableBytes), format: .byteCount(style: .file))) in all. Volumes of installed services are kept.")
        }
        .alert("Remove this image?", isPresented: Binding(get: { imageToRemove != nil },
                                                         set: { if !$0 { imageToRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let image = imageToRemove { Task { await model.removeImage(image) } }
                imageToRemove = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { imageToRemove = nil }
        } message: { Text(verbatim: imageToRemove?.name ?? "") }
        .alert("Remove this volume?", isPresented: Binding(get: { volumeToRemove != nil },
                                                          set: { if !$0 { volumeToRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let volume = volumeToRemove { Task { await model.removeVolume(volume) } }
                volumeToRemove = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { volumeToRemove = nil }
        } message: { Text("The data in it is deleted and cannot be brought back.") }
        .alert("Remove this network?", isPresented: Binding(get: { networkToRemove != nil },
                                                           set: { if !$0 { networkToRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let network = networkToRemove { Task { await model.removeNetwork(network) } }
                networkToRemove = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { networkToRemove = nil }
        } message: { Text(verbatim: networkToRemove?.name ?? "") }
    }

    @ViewBuilder
    private var imageRows: some View {
        ForEach(model.images) { image in
            assetRow(title: image.name, size: image.sizeBytes, inUse: image.isInUse,
                     removable: !image.isInUse) { imageToRemove = image }
        }
        if model.images.isEmpty && !model.isLoading { Text("No images").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var volumeRows: some View {
        ForEach(model.volumes) { volume in
            assetRow(title: volume.name, size: volume.sizeBytes, inUse: volume.isInUse || volume.isManaged,
                     removable: volume.isRemovable) { volumeToRemove = volume }
        }
        if model.volumes.isEmpty && !model.isLoading { Text("No volumes").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var systemRows: some View {
        LabeledContent("Images", value: "\(model.images.count)")
        LabeledContent("Volumes", value: "\(model.volumes.count)")
        LabeledContent("Disk used") {
            Text(Int64(model.totalBytes), format: .byteCount(style: .file))
        }
        LabeledContent("Can be freed") {
            Text(Int64(model.reclaimableBytes), format: .byteCount(style: .file))
        }
    }

    private func assetRow(title: String, size: UInt64, inUse: Bool, removable: Bool,
                          remove: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).lineLimit(1).truncationMode(.middle)
                Text(inUse ? "In use" : "Unused").font(.caption)
                    .foregroundStyle(inUse ? Color.secondary : Color.orange)
            }
            Spacer()
            Text(Int64(size), format: .byteCount(style: .file)).font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            if removable {
                Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }.dangerTint()
            }
        }
        .contextMenu {
            if removable {
                Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
                .dangerTint()
            }
        }
    }
}
