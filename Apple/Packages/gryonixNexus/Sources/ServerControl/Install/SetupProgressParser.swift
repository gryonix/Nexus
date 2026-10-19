/// Event emitted while a generated setup script runs on the server.
public enum SetupEvent: Sendable, Hashable {
    /// Progress marker: the script entered step `index` of `total`
    case step(index: Int, total: Int)
    case stage(String)
    case line(String)
    case report(String)
    case done
    case reconnecting(attempt: Int)
}

public struct SetupProgressParser: Sendable {
    private enum Marker {
        static let step = "GRYONIXNEXUS_STEP "
        static let reportBegin = "GRYONIXNEXUS_REPORT_BEGIN"
        static let reportEnd = "GRYONIXNEXUS_REPORT_END"
        static let done = "GRYONIXNEXUS_DONE"
    }

    public static let exitMarker = "GRYONIXNEXUS_EXIT:"

    private var buffer = ""
    private var reportLines: [String]?
    /// True once the DONE marker has been seen
    public private(set) var sawDone = false
    /// Last observed progress, for UIs that attach mid-stream
    public private(set) var currentStep: (index: Int, total: Int)?
    public private(set) var exitCode: Int32?

    public init() {}

    public mutating func consume(_ text: String) -> [SetupEvent] {
        buffer += text
        var events: [SetupEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            events.append(contentsOf: parse(line: line))
        }
        return events
    }

    /// Drops a buffered partial line before re-attaching to a log
    public mutating func discardPartialLine() {
        buffer = ""
    }

    public mutating func finish() -> [SetupEvent] {
        guard !buffer.isEmpty else { return [] }
        let line = buffer
        buffer = ""
        return parse(line: line)
    }

    private mutating func parse(line raw: String) -> [SetupEvent] {
        // Package managers redraw progress with ANSI codes and bare CRs.
        let line = ANSIStripper.strip(raw)

        if line.hasPrefix(Marker.step) {
            let parts = line.dropFirst(Marker.step.count).split(separator: "/")
            if parts.count == 2, let index = Int(parts[0]), let total = Int(parts[1]) {
                currentStep = (index, total)
                return [.step(index: index, total: total)]
            }
        }
        if line.hasPrefix(Self.exitMarker) {
            exitCode = Int32(line.dropFirst(Self.exitMarker.count)
                .trimmingCharacters(in: .whitespaces)) ?? 0
            return []
        }
        switch line {
        case Marker.reportBegin:
            reportLines = []
            return []
        case Marker.reportEnd:
            let report = (reportLines ?? []).joined(separator: "\n")
            reportLines = nil
            return [.report(report)]
        case Marker.done:
            sawDone = true
            return [.done]
        default:
            break
        }

        reportLines?.append(line)
        if line.hasPrefix("==> ") {
            let title = String(line.dropFirst(4))
            return [.stage(title), .line(line)]
        }
        return [.line(line)]
    }
}
