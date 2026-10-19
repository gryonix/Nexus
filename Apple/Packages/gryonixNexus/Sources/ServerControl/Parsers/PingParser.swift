import Foundation

public enum PingParser {
    public static func parse(_ output: String) throws -> PingResult {
        for line in output.split(separator: "\n") where line.contains("transmitted") {
            let fields = line.split(separator: ",")
            guard fields.count >= 2,
                  let transmitted = leadingInt(fields[0]),
                  let received = leadingInt(fields[1]) else { continue }
            return PingResult(transmitted: transmitted, received: received)
        }
        throw ServerControlError.parseFailure(
            command: "ping",
            detail: "no 'transmitted/received' statistics line in output"
        )
    }

    private static func leadingInt(_ field: Substring) -> Int? {
        let digits = field.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        return Int(digits)
    }
}
