import Foundation

/// The themes that ship with the app.
public enum TerminalThemes {
    public static let defaultDarkID = "default-dark"
    public static let defaultLightID = "default-light"

    public static func find(_ id: String, custom: [TerminalTheme] = []) -> TerminalTheme? {
        (builtIn + custom).first { $0.id == id }
    }

    private static func make(_ id: String, _ name: String, bg: String, fg: String,
                             cursor: String, selection: String, _ ansi: String) -> TerminalTheme {
        TerminalTheme(id: id, name: name, background: bg, foreground: fg, cursor: cursor,
                      selection: selection,
                      ansi: ansi.split(separator: " ").map { "#" + $0.uppercased() })
    }

    public static let builtIn: [TerminalTheme] = [
        make(defaultDarkID, "Default dark", bg: "10121A", fg: "E6E6E6", cursor: "E6E6E6", selection: "2F3446",
             "000000 CD3131 0DBC79 E5E510 2472C8 BC3FBC 11A8CD E5E5E5 666666 F14C4C 23D18B F5F543 3B8EEA D670D6 29B8DB FFFFFF"),
        make(defaultLightID, "Default light", bg: "FFFFFF", fg: "1F2328", cursor: "1F2328", selection: "B6D6FD",
             "24292F CF222E 116329 4D2D00 0969DA 8250DF 1B7C83 6E7781 57606A A40E26 1A7F37 633C01 218BFF A475F9 3192AA 8C959F"),
        make("solarized-dark", "Solarized Dark", bg: "002B36", fg: "839496", cursor: "93A1A1", selection: "073642",
             "073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 002B36 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3"),
        make("solarized-light", "Solarized Light", bg: "FDF6E3", fg: "657B83", cursor: "586E75", selection: "EEE8D5",
             "073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 002B36 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3"),
        make("dracula", "Dracula", bg: "282A36", fg: "F8F8F2", cursor: "F8F8F2", selection: "44475A",
             "21222C FF5555 50FA7B F1FA8C BD93F9 FF79C6 8BE9FD F8F8F2 6272A4 FF6E6E 69FF94 FFFFA5 D6ACFF FF92DF A4FFFF FFFFFF"),
        make("nord", "Nord", bg: "2E3440", fg: "D8DEE9", cursor: "D8DEE9", selection: "434C5E",
             "3B4252 BF616A A3BE8C EBCB8B 81A1C1 B48EAD 88C0D0 E5E9F0 4C566A BF616A A3BE8C EBCB8B 81A1C1 B48EAD 8FBCBB ECEFF4"),
        make("gruvbox-dark", "Gruvbox Dark", bg: "282828", fg: "EBDBB2", cursor: "EBDBB2", selection: "504945",
             "282828 CC241D 98971A D79921 458588 B16286 689D6A A89984 928374 FB4934 B8BB26 FABD2F 83A598 D3869B 8EC07C EBDBB2"),
        make("one-dark", "One Dark", bg: "282C34", fg: "ABB2BF", cursor: "528BFF", selection: "3E4451",
             "282C34 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 ABB2BF 5C6370 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 FFFFFF"),
        make("monokai", "Monokai", bg: "272822", fg: "F8F8F2", cursor: "F8F8F0", selection: "49483E",
             "272822 F92672 A6E22E F4BF75 66D9EF AE81FF A1EFE4 F8F8F2 75715E F92672 A6E22E F4BF75 66D9EF AE81FF A1EFE4 F9F8F5"),
        make("tomorrow-night", "Tomorrow Night", bg: "1D1F21", fg: "C5C8C6", cursor: "AEAFAD", selection: "373B41",
             "1D1F21 CC6666 B5BD68 F0C674 81A2BE B294BB 8ABEB7 C5C8C6 969896 CC6666 B5BD68 F0C674 81A2BE B294BB 8ABEB7 FFFFFF"),
        make("production-red", "Production red", bg: "1E0C0C", fg: "F2D6D6", cursor: "FF6B6B", selection: "5A2020",
             "2A1010 FF5C5C 8FD18F FFC857 7AA7E6 D97BC0 6CCFCF EBCFCF 6B3B3B FF8080 A9E5A9 FFD98A 9DC0F0 E79BD3 8FE0E0 FFFFFF"),
    ]
}
