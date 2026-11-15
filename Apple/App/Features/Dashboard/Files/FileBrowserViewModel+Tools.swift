import Foundation
import ServerControl

extension FileBrowserViewModel {
    var breadcrumbs: [RemoteBreadcrumb] { RemotePath.breadcrumbs(of: path) }

    var shownEntries: [RemoteFileEntry] { searchResults ?? entries }

    // MARK: - Rename

    func rename(_ entry: RemoteFileEntry, to newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard RemotePath.isValidName(name), name != entry.name else { return }
        await run {
            let session = try await self.connect()
            let target = RemotePath.join(RemotePath.parent(of: entry.path), name)
            try await session.renameFile(from: entry.path, to: target, on: self.host)
            self.shortcuts.renamed(entry.path, to: target)
            self.saveShortcuts()
            try await self.reloadAfterChange()
        }
    }

    func batchPlan(find: String, replace: String) -> [BatchRename.Change] {
        let chosen = entries.filter { selection.contains($0.path) }.map(\.name)
        return BatchRename.plan(names: chosen, existing: Set(entries.map(\.name)),
                                find: find, replace: replace)
    }

    func batchRename(find: String, replace: String) async {
        let changes = batchPlan(find: find, replace: replace)
        guard !changes.isEmpty else { return }
        await run {
            let session = try await self.connect()
            for change in changes {
                let from = RemotePath.join(self.path, change.oldName)
                let to = RemotePath.join(self.path, change.newName)
                try await session.renameFile(from: from, to: to, on: self.host)
                self.shortcuts.renamed(from, to: to)
            }
            self.saveShortcuts()
            self.selection = []
            try await self.reloadAfterChange()
        }
    }

    // MARK: - Search

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelSearch()
            return
        }
        isSearching = true
        let root = path
        searchTask = Task {
            do {
                let session = try await connect()
                let found = try await session.searchFiles(under: root, matching: trimmed,
                                                         limit: FileSearch.defaultLimit, on: host)
                if !Task.isCancelled { searchResults = found }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
            isSearching = false
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchResults = nil
    }

    // MARK: - Preview, thumbnails, shortcuts

    func preview(_ entry: RemoteFileEntry) async {
        guard entry.previewKind != .none else { return }
        isTransferring = true
        defer { isTransferring = false }
        await run {
            let session = try await self.connect()
            let data = try await session.downloadFile(entry.path, on: self.host, maxBytes: Self.downloadLimit)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(entry.name)
            try data.write(to: url, options: .atomic)
            self.noteOpened(entry.path)
            self.previewURL = url
        }
    }

    func endPreview() {
        if let url = previewURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        previewURL = nil
    }

    func thumbnail(for entry: RemoteFileEntry) async -> Data? {
        guard entry.canThumbnail else { return nil }
        let key = "\(deployment.id)\(entry.path)\(entry.size ?? 0)\(entry.modified?.timeIntervalSince1970 ?? 0)"
        if let cached = await FileThumbnailCache.shared.data(for: key) { return cached }
        guard let session = try? await connect(),
              let data = try? await session.downloadFile(entry.path, on: host,
                                                        maxBytes: RemoteFileEntry.thumbnailLimit)
        else { return nil }
        await FileThumbnailCache.shared.store(data, for: key)
        return data
    }

    func toggleBookmark(_ path: String) {
        shortcuts.toggleBookmark(path)
        saveShortcuts()
    }

    func noteOpened(_ path: String) {
        shortcuts.noteOpened(path)
        saveShortcuts()
    }

    func openShortcut(_ target: String) async {
        cancelSearch()
        let session = try? await connect()
        let listing = try? await session?.listDirectory(target, on: host)
        if listing != nil {
            await navigate(to: target)
            return
        }
        await navigate(to: RemotePath.parent(of: target))
        if let entry = entries.first(where: { $0.path == target }) { await preview(entry) }
    }

    func reloadAfterChange() async throws {
        let session = try await connect()
        entries = try await session.listDirectory(path, on: host)
        searchResults = nil
    }

    func saveShortcuts() {
        shortcutsStore.save(shortcuts)
    }
}
