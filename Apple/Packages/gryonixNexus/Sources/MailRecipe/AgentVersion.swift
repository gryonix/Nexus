import Foundation

public enum AgentVersion {
    /// Numeric components, ignoring anything that is not a number
    static func components(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first?.isNumber == true else { return nil }
        let parts = trimmed
            .split(whereSeparator: { ".-+".contains($0) })
            .map { $0.prefix { $0.isNumber } }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.compactMap { Int($0) }
    }

    /// Is `candidate` a LATER version than `installed`?
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let a = components(candidate), let b = components(installed) else { return false }
        for index in 0 ..< max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
