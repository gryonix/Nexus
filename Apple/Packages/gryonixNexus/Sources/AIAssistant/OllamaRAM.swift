import Foundation

public enum RAMVerdict: Equatable, Sendable {
    case enough
    case tooLow(needGB: Int, haveGB: Int)
    case unknown
}

/// Rough memory a model needs, from its parameter count.
public enum OllamaRAM {
    public static let suggestedModels = [
        "llama3.2:3b", "qwen2.5:7b", "llama3.1:8b", "qwen2.5:14b", "qwen2.5:32b"
    ]

    public static func parametersInBillions(_ model: String) -> Double? {
        let name = model.lowercased()
        if let mixture = firstMatch("(\\d+)x(\\d+(?:\\.\\d+)?)b(?![a-z])", in: name), mixture.count == 2 {
            return mixture[0] * mixture[1]
        }
        return firstMatch("(?<![a-z0-9.])(\\d+(?:\\.\\d+)?)b(?![a-z])", in: name)?.first
    }

    public static func requiredGB(model: String) -> Int? {
        guard let size = parametersInBillions(model) else { return nil }
        switch size {
        case ...3: return 4
        case ...8: return 8
        case ...14: return 16
        case ...29: return 24
        default: return 32
        }
    }

    public static func verdict(model: String, machineBytes: UInt64?) -> RAMVerdict {
        guard let need = requiredGB(model: model), let bytes = machineBytes, bytes > 0 else { return .unknown }
        let have = Int((Double(bytes) / 1_073_741_824).rounded())
        return have >= need ? .enough : .tooLow(needGB: need, haveGB: have)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: text).flatMap { Double(text[$0]) }
        }
    }
}
