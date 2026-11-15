import ServerControl
import SwiftUI

struct BreadcrumbBar: View {
    let crumbs: [RemoteBreadcrumb]
    let onSelect: (RemoteBreadcrumb) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(crumbs) { crumb in
                        if crumb.path != "/" {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button(crumb.name) { onSelect(crumb) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(crumb.id == crumbs.last?.id ? .semibold : .regular))
                            .foregroundStyle(crumb.id == crumbs.last?.id ? Color.primary : Color.accentColor)
                            .id(crumb.id)
                    }
                }
            }
            .onChange(of: crumbs) { _, new in
                if let last = new.last { proxy.scrollTo(last.id, anchor: .trailing) }
            }
        }
    }
}

struct FileThumbnail: View {
    let entry: RemoteFileEntry
    let loader: (RemoteFileEntry) async -> Data?
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: entry.previewKind == .image ? "photo" : "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: entry.id) {
            guard entry.canThumbnail, let data = await loader(entry) else { return }
            image = Self.decode(data)
        }
    }

    private static func decode(_ data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #else
        return NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}

struct FileShortcutsSheet: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section("Bookmarks", paths: viewModel.shortcuts.bookmarks, icon: "bookmark")
                section("Recent", paths: viewModel.shortcuts.recents, icon: "clock")
                if viewModel.shortcuts.bookmarks.isEmpty && viewModel.shortcuts.recents.isEmpty {
                    Text("No bookmarks or recent files yet").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, paths: [String], icon: String) -> some View {
        if !paths.isEmpty {
            Section(title) {
                ForEach(paths, id: \.self) { path in
                    Button {
                        dismiss()
                        Task { await viewModel.openShortcut(path) }
                    } label: {
                        VStack(alignment: .leading) {
                            Label(RemotePath.name(of: path), systemImage: icon)
                            Text(path).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    }
                }
            }
        }
    }
}

struct BatchRenameSheet: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var find = ""
    @State private var replace = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Find", text: $find).autocorrectionDisabled()
                    TextField("Replace with", text: $replace).autocorrectionDisabled()
                }
                Section("Result") {
                    let plan = viewModel.batchPlan(find: find, replace: replace)
                    if plan.isEmpty {
                        Text("No names would change").foregroundStyle(.secondary)
                    }
                    ForEach(plan, id: \.oldName) { change in
                        VStack(alignment: .leading) {
                            Text(change.oldName).font(.caption).foregroundStyle(.secondary)
                            Text(change.newName)
                        }
                    }
                }
            }
            .navigationTitle("Rename selected")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        dismiss()
                        Task { await viewModel.batchRename(find: find, replace: replace) }
                    }
                    .disabled(viewModel.batchPlan(find: find, replace: replace).isEmpty)
                }
            }
        }
    }
}
