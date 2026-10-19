import Foundation

/// A swap file, made once and kept across restarts
public struct SwapPlan: Sendable, Hashable {
    public let sizeGB: Int

    public static let doneMarker = "GRYONIXNEXUS_SWAP_DONE"
    public static let path = "/swapfile-gryonixnexus"
    /// Sizes the app offers
    public static let sizes = [1, 2, 4, 8]
    /// Sizes a custom value may take
    public static let allowed = 1...256

    public init(sizeGB: Int) { self.sizeGB = sizeGB }

    /// The smallest offered size that covers the missing memory
    public static func suggested(memoryBytes: Int64, needBytes: Int64) -> Int {
        let missing = Double(max(needBytes - memoryBytes, 0)) / 1_073_741_824
        return sizes.first { Double($0) >= missing } ?? sizes.last ?? 2
    }

    public func script() -> String {
        [
            "#!/bin/bash",
            "set -euo pipefail",
            "FILE=\(Self.path)",
            "SIZE_MB=\(sizeGB * 1024)",
            "if swapon --show=NAME --noheadings | grep -qx \"$FILE\"; then swapoff \"$FILE\"; fi",
            "rm -f \"$FILE\"",
            "FREE_MB=$(( $(df -B1 --output=avail / | tail -n 1 | tr -d ' ') / 1048576 ))",
            "if [ \"$SIZE_MB\" -ge \"$FREE_MB\" ]; then echo \"not enough disk: $((FREE_MB / 1024)) GB free\" >&2; exit 3; fi",
            "fallocate -l \"${SIZE_MB}M\" \"$FILE\" 2>/dev/null || dd if=/dev/zero of=\"$FILE\" bs=1M count=\"$SIZE_MB\" status=none",
            "chmod 600 \"$FILE\"",
            "mkswap \"$FILE\" >/dev/null",
            "swapon \"$FILE\"",
            "grep -q \"^$FILE \" /etc/fstab || echo \"$FILE none swap sw 0 0\" >> /etc/fstab",
            "echo \(Self.doneMarker)",
        ].joined(separator: "\n") + "\n"
    }
}
