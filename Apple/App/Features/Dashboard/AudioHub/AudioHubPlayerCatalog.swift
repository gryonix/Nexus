import SwiftUI

/// The hub players' options, keyed as the agent names them
enum AudioHubPlayerCatalog {
    static let spotify: [SpeakerSetting] = [
        SpeakerSetting(key: "bitrate", title: "Sound quality",
                       info: "Higher quality uses more internet. 320 kbit/s needs Spotify Premium. Default: 160 kbit/s.",
                       control: .choice([("96", "96 kbit/s"), ("160", "160 kbit/s"), ("320", "320 kbit/s")])),
        SpeakerSetting(key: "volume", title: "Starting volume",
                       info: "The volume the speaker starts at when Spotify connects. Default: 90%.",
                       control: .number(standard: 90, step: 5, unit: "%"), limits: 0...100),
        SpeakerSetting(key: "normalise", title: "Even out the volume",
                       info: "Plays every song at about the same loudness, so a quiet track is not followed by a loud one.",
                       control: .toggle),
        SpeakerSetting(key: "pregain", title: "Boost when evening out",
                       info: "How many dB louder the music plays while the volume is evened out. Default: 0 dB.",
                       control: .number(standard: 0, step: 1, unit: "dB"), limits: -10...10),
        SpeakerSetting(key: "volume_controller", title: "Volume control",
                       info: "Whether the volume slider in Spotify changes this speaker. A fixed volume leaves it to the amplifier.",
                       control: .choice([("softvol", "In Spotify"), ("none", "Fixed volume")])),
        SpeakerSetting(key: "device_type", title: "Icon in Spotify",
                       info: "The picture Spotify shows next to this speaker in its list of devices.",
                       control: .choice(deviceTypes)),
        SpeakerSetting(key: "autoplay", title: "Keep playing similar music",
                       info: "When an album or playlist ends, Spotify goes on with similar songs.",
                       control: .toggle),
    ]

    private static let deviceTypes: [(value: String, label: LocalizedStringKey)] = [
        ("speaker", "Speaker"), ("avr", "AV receiver"), ("tv", "TV"),
        ("computer", "Computer"), ("stb", "Set-top box"), ("audiodongle", "Audio dongle"),
    ]

    static let airPlay = SpeakerSettingsCatalog.sound + SpeakerSettingsCatalog.timing + SpeakerSettingsCatalog.sessions

    static let library: [SpeakerSetting] = [
        SpeakerSetting(key: "replaygain", title: "Even out the volume",
                       info: "Uses the loudness stored in the music files: per song, per album, or the player decides.",
                       control: .choice([("off", "Off"), ("track", "Per song"), ("album", "Per album"), ("auto", "Automatic")])),
        SpeakerSetting(key: "auto_update", title: "Find new music by itself",
                       info: "Adds songs to the library as soon as they appear in the music folder.",
                       control: .toggle),
    ]
}
