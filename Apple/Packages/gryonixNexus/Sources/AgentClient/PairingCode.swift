import Foundation

/// Parsing for the code `gryonixnexusd pair-code` prints
public enum PairingCode {
    public static func parse(_ output: String) -> String? {
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }),
            let token = line.split(whereSeparator: \.isWhitespace).last
        else { return nil }
        let code = String(token)
        return code.isEmpty ? nil : code
    }
}
