#if DEBUG
import Foundation

enum LiveActivityProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_LIVE_RUN"] != nil
    }

    /// A burst of lines, then a long silent step
    @MainActor
    static func runBurst() async {
        #if os(iOS)
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ISLAND_CHECK"] != nil {
            _ = await IslandCheck.run()
            return
        }
        #endif
        guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_LIVE_BURST"] != nil else { return }
        let island = IslandRun(title: UIL10n.string("Updating the system"),
                               serverName: "probe.example.com", progressText: "Starting…")
        for line in 1...5 {
            island.update("burst line \(line) of 5", progress: Double(line) / 10)
            try? await Task.sleep(for: .milliseconds(200))
        }
        try? await Task.sleep(for: .seconds(12))
        island.finish("Updated.")
    }

    /// Where the report is written
    static let fileName = "live-activity.txt"

    /// One line, appended
    static func note(_ line: String) {
        guard isEnabled else { return }
        let path = NSTemporaryDirectory() + fileName
        let stamped = "\(Date().timeIntervalSince1970) \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
