/// Long remote outputs (mailcow update) are shown truncated to the tail —
/// the end of the log is what tells whether the operation succeeded.
public enum OutputTail {
    public static let defaultMaxCharacters = 3000
    /// A whole operation log, kept for scrolling back
    public static let logCharacters = 200_000

    public static func tail(_ text: String, maxCharacters: Int = defaultMaxCharacters) -> String {
        guard text.count > maxCharacters else { return text }
        return "…" + String(text.suffix(maxCharacters))
    }
}
