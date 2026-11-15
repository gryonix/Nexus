import ServiceCatalog
import SwiftUI

/// How one speaker option appears on screen
struct SpeakerSetting: Identifiable {
    enum Control {
        case choice([(value: String, label: LocalizedStringKey)])
        case number(standard: Double, step: Double, unit: String)
        case buffer(minimal: Double, standard: Double, step: Double, unit: String)
        case toggle
    }

    let key: String
    let title: LocalizedStringKey
    let info: LocalizedStringKey
    let control: Control
    var limits: ClosedRange<Double>?
    var id: String { key }

    /// Lowest and highest value the file accepts
    var range: ClosedRange<Double> {
        if let limits { return limits }
        let option = ShairportSyncService.options.first { $0.key == key }
        if case .number(let low, let high) = option?.kind { return low...high }
        return 0...0
    }

    /// Each value from a start up to the highest
    func numbers(from start: Double, step: Double) -> [String] {
        let low = max(start, range.lowerBound)
        guard step > 0, range.upperBound >= low else { return [] }
        let count = Int(((range.upperBound - low) / step).rounded())
        return (0...count).map { SpeakerSettingRow.plain(low + Double($0) * step) }
    }
}

struct SpeakerSettingRow: View {
    let setting: SpeakerSetting
    @Binding var values: [String: String]

    var body: some View {
        switch setting.control {
        case .choice(let choices):
            Picker(setting.title, selection: text) {
                Text("Default").tag("")
                ForEach(choices, id: \.value) { Text($0.label).tag($0.value) }
            }
            .infoNote(setting.title, setting.info)
        case .toggle:
            Toggle(setting.title, isOn: Binding(get: { values[setting.key] == "yes" },
                                                set: { values[setting.key] = $0 ? "yes" : "" }))
                .infoNote(setting.title, setting.info)
        case .number(let standard, let step, let unit):
            SpeakerNumberRow(setting: setting, standard: standard, unit: unit, unset: "Default",
                             numbers: setting.numbers(from: setting.range.lowerBound, step: step), values: $values)
        case .buffer(let minimal, let standard, let step, let unit):
            SpeakerNumberRow(setting: setting, standard: standard, unit: unit, unset: "Automatic",
                             numbers: setting.numbers(from: minimal, step: step), values: $values)
        }
    }

    private var text: Binding<String> {
        Binding(get: { values[setting.key] ?? "" }, set: { values[setting.key] = $0 })
    }

    /// A plain decimal the config accepts, without trailing zeros
    static func plain(_ number: Double) -> String {
        var text = String(format: "%.3f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

/// A speaker number chosen on the shared wheel
struct SpeakerNumberRow: View {
    let setting: SpeakerSetting
    let standard: Double
    let unit: String
    let unset: LocalizedStringKey
    let numbers: [String]
    @Binding var values: [String: String]

    private var stored: String { values[setting.key] ?? "" }
    private var standardText: String { SpeakerSettingRow.plain(standard) }

    /// The stored value; the standard one counts as unset
    private var chosen: String { stored == standardText ? "" : stored }

    var body: some View {
        WheelRow(title: setting.title, info: setting.info, choices: choices,
                 selection: Binding(get: { chosen }, set: { values[setting.key] = $0 }),
                 startsOpen: startsOpen, text: valueText, line: wheelLabel)
    }

    private var startsOpen: Bool {
        #if DEBUG
        DemoSpeakerScreen.asked == "wheel"
        #else
        false
        #endif
    }

    private func valueText(_ choice: String) -> Text {
        choice.isEmpty ? Text(unset) : Text(verbatim: "\(choice) \(unit)").monospacedDigit()
    }

    /// Every step, the standard one named as unset
    private var choices: [String] {
        var all = numbers.map { $0 == standardText ? "" : $0 }
        if !all.contains("") { all.append("") }
        if !all.contains(chosen) { all.append(chosen) }
        return all.sorted { number($0) < number($1) }
    }

    private func number(_ choice: String) -> Double {
        Double(choice) ?? standard
    }

    private func wheelLabel(_ choice: String) -> Text {
        guard choice.isEmpty else { return valueText(choice) }
        return Text("\(Text(unset)) \(Text(verbatim: "· \(standardText) \(unit)").monospacedDigit())")
    }
}
