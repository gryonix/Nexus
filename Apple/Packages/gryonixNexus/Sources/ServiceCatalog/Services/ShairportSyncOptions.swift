/// The speaker's extra settings, as shairport-sync.conf.
extension ShairportSyncService {
    public static let configFile = "shairport-sync.conf"

    /// How one option's value is checked and written
    public enum OptionKind: Sendable, Equatable {
        case choice([String])
        case number(Double, Double)
        case control
    }

    public struct Option: Sendable, Equatable {
        public let section: String
        public let key: String
        public let kind: OptionKind
    }

    /// Every option the app may set, in file order
    public static let options: [Option] = [
        Option(section: "general", key: "interpolation", kind: .choice(["auto", "basic", "soxr"])),
        Option(section: "general", key: "volume_range_db", kind: .number(30, 100)),
        Option(section: "general", key: "volume_max_db", kind: .number(-96, 24)),
        Option(section: "general", key: "ignore_volume_control", kind: .choice(["yes", "no"])),
        Option(section: "general", key: "default_airplay_volume", kind: .number(-30, 0)),
        Option(section: "general", key: "audio_backend_latency_offset_in_seconds", kind: .number(-1, 1)),
        Option(section: "general", key: "audio_backend_buffer_desired_length_in_seconds", kind: .number(0.01, 1.5)),
        Option(section: "general", key: "drift_tolerance_in_seconds", kind: .number(0.001, 0.02)),
        Option(section: "general", key: "allow_session_interruption", kind: .choice(["yes", "no"])),
        Option(section: "general", key: "session_timeout", kind: .number(20, 3600)),
        Option(section: "alsa", key: "mixer_control_name", kind: .control),
        Option(section: "alsa", key: "output_rate", kind: .choice(["auto", "44100", "88200", "176400", "352800"])),
        Option(section: "alsa", key: "output_format", kind: .choice(["auto", "S16", "S16_LE", "S24", "S24_3LE", "S32"])),
        Option(section: "alsa", key: "disable_standby_mode", kind: .choice(["never", "auto", "always"])),
        Option(section: "alsa", key: "disable_synchronization", kind: .choice(["yes", "no"])),
        Option(section: "cec", key: "cec_volume", kind: .choice(["yes", "no"])),
        Option(section: "cec", key: "cec_volume_min", kind: .number(0, 100)),
        Option(section: "cec", key: "cec_volume_max", kind: .number(1, 100)),
        Option(section: "cec", key: "cec_tv_wakes", kind: .choice(["yes", "no"])),
        Option(section: "cec", key: "cec_tv_wait", kind: .number(10, 180)),
        Option(section: "cec", key: "cec_keep_connected", kind: .choice(["yes", "no"])),
        Option(section: "cec", key: "cec_off_delay", kind: .number(1, 60)),
        Option(section: "cec", key: "cec_grace", kind: .number(5, 120)),
    ]

    /// The speaker's own volume, moved over HDMI
    public struct CECVolume: Sendable, Equatable {
        public let enabled: Bool
        public let lowest: Int
        public let highest: Int
        public let tvOff: Bool
        public let tvWait: Int
        public let disconnect: Bool
        public let offDelay: Int
        public let grace: Int

        public init(enabled: Bool, lowest: Int, highest: Int, tvOff: Bool = true, tvWait: Int = 60,
                    disconnect: Bool = true, offDelay: Int = 2, grace: Int = 15) {
            self.enabled = enabled
            self.lowest = lowest
            self.highest = highest
            self.tvOff = tvOff
            self.tvWait = tvWait
            self.disconnect = disconnect
            self.offDelay = offDelay
            self.grace = grace
        }
    }

    public static let cecPipeDirectory = "/run/shairport-sync"
    public static let cecDefaultLowest = 1
    public static let cecDefaultHighest = 40

    /// HDMI volume settings, defaults where missing or bad
    public static func cecVolume(_ context: ServiceContext) -> CECVolume {
        let given = parsedOptions(context.settings.shairportOptions)
        func number(_ key: String, _ fallback: Int) -> Int {
            let text = given.last(where: { $0.key == key })?.value ?? ""
            guard let kind = options.first(where: { $0.key == key })?.kind,
                  rendered(kind, text) != nil, let value = Int(text) else { return fallback }
            return value
        }
        let lowest = number("cec_volume_min", cecDefaultLowest)
        let highest = number("cec_volume_max", cecDefaultHighest)
        return CECVolume(
            enabled: given.last(where: { $0.key == "cec_volume" })?.value == "yes",
            lowest: min(lowest, highest - 1), highest: highest,
            tvOff: given.last(where: { $0.key == "cec_tv_wakes" })?.value != "yes",
            tvWait: number("cec_tv_wait", 60),
            disconnect: given.last(where: { $0.key == "cec_keep_connected" })?.value != "yes",
            offDelay: number("cec_off_delay", 2), grace: number("cec_grace", 15))
    }

    /// The options string as key and value pairs
    public static func parsedOptions(_ text: String) -> [(key: String, value: String)] {
        text.split(separator: ";", omittingEmptySubsequences: true).compactMap { pair in
            guard let equals = pair.firstIndex(of: "=") else { return nil }
            let key = pair[..<equals].trimmingCharacters(in: .whitespaces)
            let value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return (key, value)
        }
    }

    /// Pairs back into the stored string
    public static func optionsText(_ values: [String: String]) -> String {
        options.compactMap { option in
            guard let value = values[option.key], !value.isEmpty else { return nil }
            return "\(option.key)=\(value)"
        }.joined(separator: ";")
    }

    /// The written form of a valid value, or nil
    public static func rendered(_ kind: OptionKind, _ value: String) -> String? {
        switch kind {
        case .choice(let allowed):
            guard allowed.contains(value) else { return nil }
            return value.allSatisfy(\.isASCIIDigit) ? value : "\"\(value)\""
        case .number(let low, let high):
            let digits = value.hasPrefix("-") ? String(value.dropFirst()) : value
            let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let plain = parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }
            guard plain, let number = Double(value), number >= low, number <= high else { return nil }
            return value
        case .control:
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-")
            guard !value.isEmpty, value.count <= 40, value.allSatisfy(allowed.contains) else { return nil }
            return "\"\(value)\""
        }
    }

    public static func configContents(_ context: ServiceContext) -> String {
        let given = parsedOptions(context.settings.shairportOptions)
        let cec = cecVolume(context).enabled
        var out = ""
        for section in ["general", "alsa"] {
            out += "\(section) = {\n"
            for option in options where option.section == section {
                let value = cec && option.key == "ignore_volume_control"
                    ? "yes" : given.last(where: { $0.key == option.key })?.value
                guard let value, let line = rendered(option.kind, value) else { continue }
                out += "  \(option.key) = \(line);\n"
            }
            out += "};\n"
        }
        return cec ? out + metadataBlock : out
    }

    private static let metadataBlock = """
    metadata = {
      enabled = "yes";
      include_cover_art = "no";
      pipe_name = "\(cecPipeDirectory)/metadata";
      pipe_timeout = 5000;
    };

    """
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
