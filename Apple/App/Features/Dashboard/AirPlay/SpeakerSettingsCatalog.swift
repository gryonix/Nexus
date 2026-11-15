import SwiftUI

/// The speaker's options, grouped as the screen shows them
enum SpeakerSettingsCatalog {
    static let sound: [SpeakerSetting] = [
        SpeakerSetting(key: "ignore_volume_control", title: "Ignore the volume from the phone",
                       info: "The phone's volume slider stops changing this speaker; it always plays at its own level. Turn this on when an amplifier or the TV sets the volume.", control: .toggle),
        SpeakerSetting(key: "default_airplay_volume", title: "Starting volume",
                       info: "The volume the speaker begins at when a device starts playing. 0 dB is the loudest, -30 dB is very quiet. Default: -24 dB.",
                       control: .number(standard: -24, step: 1, unit: "dB")),
        SpeakerSetting(key: "volume_range_db", title: "Volume range",
                       info: "How many dB below the loudest volume the slider's lowest position is. A smaller range makes the quietest steps louder; a larger one gives finer control at low volume. Default: 60 dB.",
                       control: .number(standard: 60, step: 5, unit: "dB")),
        SpeakerSetting(key: "volume_max_db", title: "Loudest volume",
                       info: "The loudest level the speaker may reach, in dB. Lower it to cap the volume and protect the speakers or your ears. Default: 0 dB.",
                       control: .number(standard: 0, step: 1, unit: "dB")),
    ]

    static let hdmiVolume: [SpeakerSetting] = [
        SpeakerSetting(key: "cec_volume", title: "Volume on the TV or amplifier",
                       info: "The speaker sends the phone's volume to the TV or amplifier over HDMI-CEC and plays at full level itself. The device wakes up when music starts.", control: .toggle),
        SpeakerSetting(key: "cec_volume_min", title: "Lowest volume",
                       info: "The volume the TV or amplifier is set to when the phone's slider is at its lowest, on the device's own scale from 0 to 100.",
                       control: .number(standard: 1, step: 1, unit: "")),
        SpeakerSetting(key: "cec_volume_max", title: "Highest volume",
                       info: "The volume the TV or amplifier reaches when the slider is at its top. Lower it to cap the volume. On the device's own scale from 0 to 100.",
                       control: .number(standard: 40, step: 1, unit: "")),
        SpeakerSetting(key: "cec_tv_wakes", title: "Let the TV switch on",
                       info: "When music starts, the speaker switches to this input and the TV may switch on with it. Off: the speaker puts a TV that was off back to standby right away.",
                       control: .toggle),
        SpeakerSetting(key: "cec_tv_wait", title: "How long to wait for the TV",
                       info: "When the TV is sent back to standby, the speaker waits this many seconds for it to wake up and start listening first. Used only when the TV may not switch on. Default: 60 s.",
                       control: .number(standard: 60, step: 5, unit: "s")),
        SpeakerSetting(key: "cec_keep_connected", title: "Keep AirPlay when the speaker turns off",
                       info: "When off, AirPlay is disconnected a few seconds after the speaker itself is switched off, so the phone stops playing into the void. When on, the connection stays.",
                       control: .toggle),
        SpeakerSetting(key: "cec_off_delay", title: "Delay before disconnecting",
                       info: "How many seconds the speaker must stay off before AirPlay is disconnected. Default: 2 s.",
                       control: .number(standard: 2, step: 1, unit: "s")),
        SpeakerSetting(key: "cec_grace", title: "Wait after music starts",
                       info: "Seconds after music starts before the speaker is checked for being switched off. It gives a sleeping speaker time to wake up. Default: 15 s.",
                       control: .number(standard: 15, step: 1, unit: "s")),
    ]

    static let timing: [SpeakerSetting] = [
        SpeakerSetting(key: "audio_backend_latency_offset_in_seconds", title: "Sound delay (lip-sync)",
                       info: "Moves the sound earlier (minus) or later (plus) so it matches the picture, for example on a TV. Default: 0 s.",
                       control: .number(standard: 0, step: 0.01, unit: "s")),
        SpeakerSetting(key: "audio_backend_buffer_desired_length_in_seconds", title: "Buffer",
                       info: "How much sound the speaker queues up before playing it. Automatic is 0.2 s. Minimum reacts fastest to pause and volume changes, but too small a buffer on weak Wi‑Fi makes the sound drop out.",
                       control: .buffer(minimal: 0.03, standard: 0.2, step: 0.01, unit: "s")),
        SpeakerSetting(key: "drift_tolerance_in_seconds", title: "Drift tolerance",
                       info: "How far the sound may drift from the sender's clock before the speaker corrects it. A smaller value keeps the sound tighter in sync but corrects more often, which can be audible. Default: 0.002 s.",
                       control: .number(standard: 0.002, step: 0.001, unit: "s")),
        SpeakerSetting(key: "interpolation", title: "Resampling",
                       info: "How the speaker speeds up or slows down the sound a little to stay in sync. Basic is the lightest; High quality (SoX) sounds cleanest but needs more processor power, which a small Raspberry Pi may lack. Automatic lets the speaker pick.", control: .choice([
            ("auto", "Automatic"), ("basic", "Basic"), ("soxr", "High quality (SoX)"),
        ])),
    ]

    static let format: [SpeakerSetting] = [
        SpeakerSetting(key: "output_rate", title: "Sample rate",
                       info: "The sample rate sent to the sound card. Automatic lets the card choose, usually 44.1 kHz. Change it only when your card or amplifier needs a specific rate.", control: .choice([
            ("auto", "Automatic"), ("44100", "44.1 kHz"), ("88200", "88.2 kHz"),
            ("176400", "176.4 kHz"), ("352800", "352.8 kHz"),
        ])),
        SpeakerSetting(key: "output_format", title: "Sample format",
                       info: "The bit depth sent to the sound card. Automatic picks the best one the card supports. If the sound crackles or stays silent, try 16-bit.", control: .choice([
            ("auto", "Automatic"), ("S16", "16-bit"), ("S16_LE", "16-bit LE"), ("S24", "24-bit"),
            ("S24_3LE", "24-bit packed"), ("S32", "32-bit"),
        ])),
        SpeakerSetting(key: "disable_standby_mode", title: "Keep the output awake",
                       info: "Some amplifiers click or swallow the first second of sound when the card wakes up. This keeps the output awake: never, while a device is connected, or always (even when nothing plays).", control: .choice([
            ("never", "Never"), ("auto", "While a device is connected"), ("always", "Always"),
        ])),
        SpeakerSetting(key: "disable_synchronization", title: "Turn off synchronisation",
                       info: "Stops the speaker from stretching or squeezing the sound to stay in step with the sender. The sound may drift out of sync over time. Leave it off unless you are troubleshooting.", control: .toggle),
    ]

    static let sessions: [SpeakerSetting] = [
        SpeakerSetting(key: "allow_session_interruption", title: "Let another device take over",
                       info: "When on, a second phone can start playing and take the speaker from the first. When off, the speaker stays with the first device until it stops.", control: .toggle),
        SpeakerSetting(key: "session_timeout", title: "Release after silence",
                       info: "How many seconds of silence the speaker waits before it lets go of a connected device, so another device can play. Default: 120 s.",
                       control: .number(standard: 120, step: 10, unit: "s")),
    ]
}
