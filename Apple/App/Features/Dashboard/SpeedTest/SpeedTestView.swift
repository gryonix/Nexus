import ServiceCatalog
import SwiftUI

/// Internet and disk speed of one server, with past runs
struct SpeedTestView: View {
    @StateObject private var model: SpeedTestViewModel

    init(target: SpeedTestTarget) {
        _model = StateObject(wrappedValue: SpeedTestViewModel(target: target))
    }

    var body: some View {
        Form {
            Section {
                SpeedResultRows(record: model.latest(SpeedTestViewModel.internet))
                runButton("Test the internet", location: SpeedTestViewModel.internet) {
                    await model.testInternet()
                }
            } header: {
                Text("Internet")
            } footer: {
                Text("Downloads 50 MB and uploads 25 MB through Cloudflare's speed server.")
            }
            ForEach(model.locations, id: \.self) { location in
                diskSection(location)
            }
            if let error = model.errorMessage {
                Section { Text(verbatim: error).foregroundStyle(.red) }
            }
            if !model.records.isEmpty {
                Section("Past tests") {
                    ForEach(model.records) { SpeedHistoryRow(record: $0) }
                }
            }
        }
        .navigationTitle("Speed test")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.loadLocations() }
    }

    private func diskSection(_ location: String) -> some View {
        Section {
            SpeedResultRows(record: model.latest(location))
            runButton("Test the disk", location: location) { await model.testDisk(location) }
        } header: {
            Text(verbatim: SpeedText.place(location))
        } footer: {
            Text(location == SpeedTest.systemDirectory
                 ? "Writes and reads a 256 MB file past the cache, then deletes it."
                 : "Writes and reads a 256 MB file as root, then deletes it.")
        }
    }

    private func runButton(_ title: LocalizedStringKey, location: String,
                           action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if model.running == location { ProgressView().controlSize(.small) }
            }
        }
        .disabled(model.running != nil)
    }
}

/// Latest numbers of one test
private struct SpeedResultRows: View {
    let record: SpeedRecord?

    var body: some View {
        if let internet = record?.internet {
            LabeledContent("Download speed") { Text(verbatim: SpeedText.bits(internet.downloadBitsPerSecond)) }
            LabeledContent("Upload speed") { Text(verbatim: SpeedText.bits(internet.uploadBitsPerSecond)) }
            LabeledContent("Ping") { Text(verbatim: SpeedText.milliseconds(internet.latencySeconds)) }
        } else if let disk = record?.disk {
            LabeledContent("Write") { Text(verbatim: SpeedText.bytes(disk.writeBytesPerSecond)) }
            LabeledContent("Read") { Text(verbatim: SpeedText.bytes(disk.readBytesPerSecond)) }
            if disk.cached {
                Label("Direct disk access is refused here, so the numbers include the memory cache.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Text("Not tested yet.").foregroundStyle(.secondary)
        }
    }
}

/// One past test in the list
private struct SpeedHistoryRow: View {
    let record: SpeedRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: summary)
            Text(record.date, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        if let net = record.internet {
            return "↓ \(SpeedText.bits(net.downloadBitsPerSecond))  ↑ \(SpeedText.bits(net.uploadBitsPerSecond))"
        }
        guard let disk = record.disk else { return "" }
        let place = SpeedText.place(record.location ?? "")
        return UIL10n.string("%@: write %@, read %@", place, SpeedText.bytes(disk.writeBytesPerSecond),
                             SpeedText.bytes(disk.readBytesPerSecond))
    }
}

/// Speed numbers as people read them
enum SpeedText {
    static func bits(_ perSecond: Double) -> String {
        UIL10n.string("%@ Mbit/s", number(perSecond / 1_000_000))
    }

    static func bytes(_ perSecond: Double) -> String {
        UIL10n.string("%@ MB/s", number(perSecond / 1_000_000))
    }

    static func milliseconds(_ seconds: Double) -> String {
        UIL10n.string("%@ ms", number(seconds * 1000))
    }

    static func place(_ location: String) -> String {
        switch location {
        case SpeedTest.systemDirectory: return UIL10n.string("System disk")
        case RaidPlan.mountPoint: return UIL10n.string("RAID array")
        default: return UIL10n.string("Disk %@", location)
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}
