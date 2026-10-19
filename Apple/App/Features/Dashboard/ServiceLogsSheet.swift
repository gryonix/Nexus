import AgentClient
import ServerControl
import ServiceCatalog
import SwiftUI

struct ServiceLogsSheet: View {
    /// Where the lines come from
    enum Source {
        case agent(serviceID: String, host: SSHHostID?)
        /// Reads one bounded tail
        case snapshot(load: @Sendable () async throws -> [String])
    }

    let deployment: Deployment
    let service: any ManagedService
    let source: Source

    @StateObject private var model = ServiceLogsModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                logBody
            }
            .navigationTitle(service.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard(model.plainText())
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(model.entries.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 440)
        #endif
        .task {
            await model.start(deployment: deployment, source: source)
        }
        .onDisappear { model.stop() }
    }

    // MARK: Chrome

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            statusLabel
            Spacer(minLength: 8)
            if model.containers.count > 1 {
                Menu {
                    Button("All containers") { model.filter = nil }
                    ForEach(model.containers, id: \.self) { container in
                        Button(container) { model.filter = container }
                    }
                } label: {
                    Label(model.filter ?? String(localized: "All containers"),
                          systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if model.isLive {
                Toggle(isOn: $model.follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
            } else {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .secondaryActionButtonStyle()
                .controlSize(.small)
                .disabled(model.status == .connecting)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.status {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
            }
        case .streaming:
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption).foregroundStyle(.green)
        case .ended:
            Label(model.isLive ? "Stream ended" : "Snapshot",
                  systemImage: model.isLive ? "stop.circle" : "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: Lines

    @ViewBuilder
    private var logBody: some View {
        let entries = model.visibleEntries
        if entries.isEmpty {
            VStack {
                Spacer()
                Text(model.status == .connecting
                     ? "Waiting for the first lines…"
                     : "No output yet.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            line(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: entries.last?.id) { _, last in
                    guard model.follow, let last else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onAppear {
                    if let last = entries.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func line(_ entry: ServiceLogsModel.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if model.filter == nil && model.containers.count > 1 {
                Text(entry.shortContainer)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
            }
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(entry.isError ? .red : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

@MainActor
final class ServiceLogsModel: ObservableObject {
    struct Entry: Identifiable {
        let id: Int
        let container: String
        let text: String
        let isError: Bool

        var shortContainer: String {
            let parts = container.split(separator: "-")
            guard parts.count > 2 else { return container }
            return parts.dropFirst().dropLast().joined(separator: "-")
        }
    }

    enum Status: Equatable {
        case connecting
        case streaming
        case ended
        case failed(String)
    }

    /// A live follow is unbounded; the buffer is not
    private static let bufferLimit = 2000

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var containers: [String] = []
    @Published private(set) var status: Status = .connecting
    @Published var follow = true
    @Published var filter: String?

    private var task: Task<Void, Never>?
    private var nextID = 0
    private var source: ServiceLogsSheet.Source?

    /// True only for the agent stream
    var isLive: Bool {
        if case .agent = source { return true }
        return false
    }

    var visibleEntries: [Entry] {
        guard let filter else { return entries }
        return entries.filter { $0.container == filter }
    }

    func plainText() -> String {
        visibleEntries.map { entry in
            containers.count > 1 ? "[\(entry.shortContainer)] \(entry.text)" : entry.text
        }.joined(separator: "\n")
    }

    func start(deployment: Deployment, source: ServiceLogsSheet.Source) async {
        guard task == nil else { return }
        self.source = source
        switch source {
        case .agent(let serviceID, let host):
            startStream(deployment: deployment, agentServiceID: serviceID, host: host)
        case .snapshot(let load):
            startSnapshot(load)
        }
    }

    /// Fetches the tail again, replacing what is on screen
    func reload() async {
        guard case .snapshot(let load) = source else { return }
        task?.cancel()
        task = nil
        entries.removeAll()
        startSnapshot(load)
    }

    private func startStream(deployment: Deployment, agentServiceID: String, host: SSHHostID?) {
        guard #available(macOS 15.0, *) else {
            status = .failed(UIL10n.string("Service logs need macOS 15 or newer."))
            return
        }
        task = Task { [weak self] in
            var session: AgentConnection.Session?
            do {
                let opened = try await AgentConnection.open(deployment: deployment, host: host)
                session = opened
                self?.status = .streaming
                for try await line in opened.client.logs(serviceID: agentServiceID) {
                    if Task.isCancelled { break }
                    self?.append(line)
                }
                self?.finish(nil)
            } catch is CancellationError {
                // Closing the sheet — nothing to report.
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self?.finish(message)
            }
            await session?.runner.disconnect()
        }
    }

    private func startSnapshot(_ load: @escaping @Sendable () async throws -> [String]) {
        status = .connecting
        task = Task { [weak self] in
            do {
                let lines = try await load()
                if Task.isCancelled { return }
                for line in lines { self?.appendPlain(line) }
                self?.finish(nil)
            } catch is CancellationError {
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self?.finish(message)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func appendPlain(_ text: String) {
        entries.append(Entry(id: nextID, container: "", text: text, isError: false))
        nextID += 1
        if entries.count > Self.bufferLimit {
            entries.removeFirst(entries.count - Self.bufferLimit)
        }
    }

    private func append(_ line: Gryonixnexusd_V1_LogLine) {
        if !line.container.isEmpty, !containers.contains(line.container) {
            containers.append(line.container)
            containers.sort()
        }
        entries.append(Entry(id: nextID, container: line.container,
                             text: line.text, isError: line.stream == "stderr"))
        nextID += 1
        if entries.count > Self.bufferLimit {
            entries.removeFirst(entries.count - Self.bufferLimit)
        }
    }

    private func finish(_ errorMessage: String?) {
        status = errorMessage.map { Status.failed($0) } ?? .ended
    }
}
