import Foundation

public enum TerminalArrow: String, Sendable { case up, down, left, right }

/// One key of the row above the keyboard.
public struct TerminalAccessoryKey: Hashable, Identifiable, Sendable {
    public enum Action: Hashable, Sendable {
        case controlToggle
        case arrow(TerminalArrow)
        case bytes([UInt8])
        case text(String)
    }

    public enum Group: String, CaseIterable, Sendable { case special, symbols, function, control }

    public let id: String
    public let label: String
    public let group: Group
    public let action: Action
}

public enum TerminalAccessoryCatalog {
    private static func escape(_ tail: String) -> [UInt8] { Array(("\u{1B}" + tail).utf8) }

    private static let special: [TerminalAccessoryKey] = [
        .init(id: "esc", label: "Esc", group: .special, action: .bytes([0x1B])),
        .init(id: "tab", label: "Tab", group: .special, action: .bytes([0x09])),
        .init(id: "ctrl", label: "Ctrl", group: .special, action: .controlToggle),
        .init(id: "up", label: "↑", group: .special, action: .arrow(.up)),
        .init(id: "down", label: "↓", group: .special, action: .arrow(.down)),
        .init(id: "left", label: "←", group: .special, action: .arrow(.left)),
        .init(id: "right", label: "→", group: .special, action: .arrow(.right)),
        .init(id: "home", label: "Home", group: .special, action: .bytes(escape("[H"))),
        .init(id: "end", label: "End", group: .special, action: .bytes(escape("[F"))),
        .init(id: "pageUp", label: "PgUp", group: .special, action: .bytes(escape("[5~"))),
        .init(id: "pageDown", label: "PgDn", group: .special, action: .bytes(escape("[6~"))),
        .init(id: "enter", label: "⏎", group: .special, action: .bytes([0x0D])),
        .init(id: "backspace", label: "⌫", group: .special, action: .bytes([0x7F])),
    ]

    private static let symbols: [TerminalAccessoryKey] = "|~/-_\\`$&*()[]{}<>=+:;\"'@#%^!?.,".map {
        .init(id: "sym-\($0)", label: String($0), group: .symbols, action: .text(String($0)))
    }

    private static let function: [TerminalAccessoryKey] = (1...12).map { number in
        let tail = number <= 4 ? "O" + String(UnicodeScalar(UInt8(79 + number))) : "[" + ["15", "17", "18", "19", "20", "21", "23", "24"][number - 5] + "~"
        return .init(id: "f\(number)", label: "F\(number)", group: .function, action: .bytes(escape(tail)))
    }

    private static let control: [TerminalAccessoryKey] = "ACDEKLRUWXZ".unicodeScalars.map { letter in
        .init(id: "ctrl-\(Character(letter))", label: "^\(Character(letter))", group: .control,
              action: .bytes([UInt8(letter.value) - 64]))
    }

    public static let all: [TerminalAccessoryKey] = special + symbols + function + control

    public static func key(_ id: String) -> TerminalAccessoryKey? { all.first { $0.id == id } }
}

/// The ordered key ids the user chose, with edits.
public struct TerminalAccessoryLayout: Codable, Equatable, Sendable {
    public static let defaultIDs = ["esc", "ctrl", "tab", "left", "down", "up", "right",
                                    "sym-|", "sym-~", "sym-/", "sym--", "ctrl-C", "ctrl-D"]

    public private(set) var ids: [String]

    public init(ids: [String] = TerminalAccessoryLayout.defaultIDs) {
        self.ids = ids
    }

    public var keys: [TerminalAccessoryKey] { ids.compactMap(TerminalAccessoryCatalog.key) }

    public mutating func add(_ id: String) {
        guard TerminalAccessoryCatalog.key(id) != nil, !ids.contains(id) else { return }
        ids.append(id)
    }

    public mutating func remove(at index: Int) {
        guard ids.indices.contains(index) else { return }
        ids.remove(at: index)
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard ids.indices.contains(source), ids.indices.contains(destination) else { return }
        ids.insert(ids.remove(at: source), at: destination)
    }

    public mutating func reset() { ids = Self.defaultIDs }
}

public struct TerminalAccessoryStore {
    private let defaults: UserDefaults
    private let key = "terminal.accessoryKeys"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> TerminalAccessoryLayout {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TerminalAccessoryLayout.self, from: $0) }
            ?? TerminalAccessoryLayout()
    }

    public func save(_ layout: TerminalAccessoryLayout) {
        defaults.set(try? JSONEncoder().encode(layout), forKey: key)
    }
}
