/// Removes terminal control noise from remote command output
/// (the mailcow updater prints colors and progress bars).
public enum ANSIStripper {
    public static func strip(_ input: String) -> String {
        var result = String.UnicodeScalarView()
        var scalars = input.unicodeScalars[...]

        while let scalar = scalars.first {
            scalars = scalars.dropFirst()
            guard scalar == "\u{1B}" else {
                result.append(scalar)
                continue
            }
            guard let next = scalars.first else { break }
            scalars = scalars.dropFirst()
            if next == "[" {
                while let byte = scalars.first {
                    scalars = scalars.dropFirst()
                    if (0x40...0x7E).contains(byte.value) { break }
                }
            } else if next == "]" {
                // OSC: terminated by BEL or ESC \.
                while let byte = scalars.first {
                    scalars = scalars.dropFirst()
                    if byte == "\u{07}" { break }
                    if byte == "\u{1B}", scalars.first == "\\" {
                        scalars = scalars.dropFirst()
                        break
                    }
                }
            }
            // Other two-byte escapes: ESC + single char, already consumed.
        }

        let stripped = String(result)
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
        let collapsed = lines.map { line -> Substring in
            guard let lastCR = line.lastIndex(of: "\r") else { return line }
            return line[line.index(after: lastCR)...]
        }
        return collapsed.joined(separator: "\n")
    }
}
