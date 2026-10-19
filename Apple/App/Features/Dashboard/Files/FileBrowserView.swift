import ServerControl
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @StateObject private var viewModel: FileBrowserViewModel
    @State private var showImporter = false
    @State private var entryPendingDelete: RemoteFileEntry?

    init(deployment: Deployment, host: SSHHostID) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(deployment: deployment, host: host))
    }

    var body: some View {
        CardList {
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                if !viewModel.isAtRoot {
                    Button {
                        Task { await viewModel.goUp() }
                    } label: {
                        Label("Up one level", systemImage: "arrow.turn.left.up")
                    }
                }

                ForEach(viewModel.entries) { entry in
                    row(entry)
                }

                if viewModel.entries.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                    Text("Empty directory")
                        .foregroundStyle(.secondary)
                }
            } header: {
                // Head truncation: with long paths the tail (current folder) matters.
                Text(viewModel.path)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.isAtRoot ? "/" : RemotePath.name(of: viewModel.path))
        .raisedNavigationTitle()
        .toolbar { browserToolbar }
        .refreshableWithShortcut { await viewModel.refresh() }
        .task { await viewModel.start() }
        .onDisappear { viewModel.teardown() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.upload(from: url) }
            }
        }
        .fileExporter(
            isPresented: exporterBinding,
            document: viewModel.pendingDownload.map { DataDocument(data: $0.data) },
            contentType: .data,
            defaultFilename: viewModel.pendingDownload?.name
        ) { _ in
            viewModel.pendingDownload = nil
        }
        .alert(
            Text("Delete \(entryPendingDelete?.name ?? "")?"),
            isPresented: deleteConfirmBinding
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryPendingDelete {
                    entryPendingDelete = nil
                    Task { await viewModel.delete(entry) }
                }
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { entryPendingDelete = nil }
        }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isTransferring {
                ProgressView()
            } else {
                Button {
                    showImporter = true
                } label: {
                    Label("Upload file", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: RemoteFileEntry) -> some View {
        if entry.kind == .directory {
            Button {
                Task { await viewModel.open(entry) }
            } label: {
                HStack {
                    Label(entry.name, systemImage: "folder")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contextMenu { deleteButton(entry) }
        } else {
            HStack {
                Label(entry.name, systemImage: entry.kind == .symlink ? "link" : "doc")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let size = entry.size {
                    Text(Int64(size), format: .byteCount(style: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    Task { await viewModel.download(entry) }
                } label: {
                    Label("Download", systemImage: "square.and.arrow.down")
                }
                deleteButton(entry)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    entryPendingDelete = entry
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .dangerTint()
            }
        }
    }

    private func deleteButton(_ entry: RemoteFileEntry) -> some View {
        Button(role: .destructive) {
            entryPendingDelete = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .dangerTint()
    }

    private var exporterBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDownload != nil },
            set: { if !$0 { viewModel.pendingDownload = nil } }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )
    }
}

struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
