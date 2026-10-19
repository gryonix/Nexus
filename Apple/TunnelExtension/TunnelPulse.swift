import Darwin
import Foundation
import VPNProfile

/// Notes every five seconds that the tunnel is alive
final class TunnelPulse: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now(), repeating: .seconds(5))
        source.setEventHandler { [weak self] in self?.beat() }
        source.resume()
        timer = source
    }

    private func beat() {
        let megabytes = Double(Self.footprint()) / 1_048_576
        TunnelStopRecord().heartbeat(String(format: "%@, memory %.1f MB (%@)",
                                            formatter.string(from: Date()), megabytes, Self.goMemory()))
    }

    private static func goMemory() -> String {
        guard let answer = GryonixGoMemory() else { return "" }
        defer { free(answer) }
        return String(cString: answer)
    }

    /// What the system counts against the extension's limit
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
