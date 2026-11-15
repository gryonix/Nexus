import ServerControl
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @StateObject private var viewModel: FileBrowserViewModel
    @State private var showImporter = false
    @State private var entryPendingDelete: RemoteFileEntry?
    @State private var entryPendingRename: RemoteFileEntry?
    @State private var searchText = ""
    @State private var selecting = false
    @State private var showShortcuts = false
    @State private var showBatchRename = false

    init(deployment: Deployment, host: SSHHostID) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(deployment: deployment, host: host))
    }

    var body: some View {
        list
            .overlay {
                if viewModel.isLoading && viewModel.entries.isEmpty { ProgressView() }
            }
            .screenTitle(viewModel.isAtRoot ? "/" : RemotePath.name(of: viewModel.path))
            .raisedNavigationTitle()
            .toolbar { browserToolbar }
            .searchable(text: $searchText, prompt: Text("Search in this folder"))
            .onSubmit(of: .search) { viewModel.search(searchText) }
            .onChange(of: searchText) { _, text in if text.isEmpty { viewModel.cancelSearch() } }
            .refreshableWithShortcut { await viewModel.refresh() }
            .task { await viewModel.start() }
            .onDisappear { viewModel.teardown() }
            .modifier(FileBrowserDialogs(viewModel: viewModel, showImporter: $showImporter,
                                         showShortcuts: $showShortcuts, showBatchRename: $showBatchRename))
            .sheet(item: $entryPendingRename) { entry in
                NameEditSheet(title: "Rename", fieldTitle: "Name", initial: entry.name) { name in
                    Task { await viewModel.rename(entry, to: name) }
                }
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

    private var list: some View {
        CardList {
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            Section {
                BreadcrumbBar(crumbs: viewModel.breadcrumbs) { crumb in
                    Task { await viewModel.jump(to: crumb.path) }
                }
            }
            Section {
                if !viewModel.isAtRoot && viewModel.searchResults == nil {
                    Button {
                        Task { await viewModel.goUp() }
                    } label: {
                        Label("Up one level", systemImage: "arrow.turn.left.up")
                    }
                }
                if viewModel.isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching").foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { viewModel.cancelSearch(); searchText = "" }
                    }
                }
                ForEach(viewModel.shownEntries) { entry in
                    row(entry)
                }
                if viewModel.shownEntries.isEmpty && !viewModel.isLoading && !viewModel.isSearching
                    && viewModel.errorMessage == nil {
                    Text(viewModel.searchResults == nil ? "Empty directory" : "Nothing found")
                        .foregroundStyle(.secondary)
                }
            } header: {
                if let results = viewModel.searchResults {
                    Text("\(results.count) found")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isTransferring {
                ProgressView()
            } else {
                Menu {
                    Button { showImporter = true } label: {
                        Label("Upload file", systemImage: "square.and.arrow.up")
                    }
                    Button { showShortcuts = true } label: {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                    Button { toggleSelecting() } label: {
                        Label(selecting ? "Done selecting" : "Select", systemImage: "checkmark.circle")
                    }
                    if selecting && !viewModel.selection.isEmpty {
                        Button { showBatchRename = true } label: {
                            Label("Rename selected", systemImage: "pencil")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func toggleSelecting() {
        selecting.toggle()
        viewModel.selection = []
    }

    @ViewBuilder
    private func row(_ entry: RemoteFileEntry) -> some View {
        Button {
            tap(entry)
        } label: {
            HStack {
                if selecting {
                    Image(systemName: viewModel.selection.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                }
                icon(entry)
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                trailing(entry)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { actions(entry) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { entryPendingDelete = entry } label: {
                Label("Delete", systemImage: "trash")
            }
            .dangerTint()
        }
    }

    @ViewBuilder
    private func icon(_ entry: RemoteFileEntry) -> some View {
        if entry.kind == .directory {
            Image(systemName: "folder").frame(width: 28, height: 28)
        } else if entry.previewKind == .image {
            FileThumbnail(entry: entry) { await viewModel.thumbnail(for: $0) }
        } else {
            Image(systemName: entry.kind == .symlink ? "link" : "doc").frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private func trailing(_ entry: RemoteFileEntry) -> some View {
        if viewModel.shortcuts.isBookmarked(entry.path) {
            Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint)
        }
        if entry.kind == .directory {
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        } else if let size = entry.size {
            Text(Int64(size), format: .byteCount(style: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tap(_ entry: RemoteFileEntry) {
        if selecting {
            if viewModel.selection.contains(entry.path) {
                viewModel.selection.remove(entry.path)
            } else {
                viewModel.selection.insert(entry.path)
            }
        } else if entry.kind == .directory {
            Task { await viewModel.open(entry) }
        } else if entry.previewKind != .none {
            Task { await viewModel.preview(entry) }
        }
    }

    @ViewBuilder
    private func actions(_ entry: RemoteFileEntry) -> some View {
        if entry.kind != .directory {
            Button {
                Task { await viewModel.download(entry) }
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
        }
        Button {
            entryPendingRename = entry
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { viewModel.toggleBookmark(entry.path) } label: {
            Label(viewModel.shortcuts.isBookmarked(entry.path) ? "Remove bookmark" : "Add bookmark",
                  systemImage: "bookmark")
        }
        deleteButton(entry)
    }

    private func deleteButton(_ entry: RemoteFileEntry) -> some View {
        Button(role: .destructive) {
            entryPendingDelete = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .dangerTint()
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )
    }
}

struct FileBrowserDialogs: ViewModifier {
    @ObservedObject var viewModel: FileBrowserViewModel
    @Binding var showImporter: Bool
    @Binding var showShortcuts: Bool
    @Binding var showBatchRename: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result {
                    Task { await viewModel.upload(from: url) }
                }
            }
            #if !os(tvOS)
            .fileExporter(
                isPresented: exporterBinding,
                document: viewModel.pendingDownload.map { DataDocument(data: $0.data) },
                contentType: .data,
                defaultFilename: viewModel.pendingDownload?.name
            ) { _ in
                viewModel.pendingDownload = nil
            }
            .quickLookPreview($viewModel.previewURL)
            #endif
            .sheet(isPresented: $showShortcuts) { FileShortcutsSheet(viewModel: viewModel) }
            .sheet(isPresented: $showBatchRename) { BatchRenameSheet(viewModel: viewModel) }
    }

    private var exporterBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDownload != nil },
            set: { if !$0 { viewModel.pendingDownload = nil } }
        )
    }
}

#if !os(tvOS)
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

#endif