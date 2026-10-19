import ServerControl
import SwiftUI

/// Price per kilowatt-hour and its currency
struct EnergyPriceSection: View {
    @ObservedObject var settings: EnergySettings

    private static let currencies = ["EUR", "USD", "GBP", "CHF", "PLN", "CZK", "SEK", "DKK", "NOK",
                                     "HUF", "RON", "BGN", "UAH", "RUB", "JPY", "CNY"]

    private var offered: [String] {
        Self.currencies.contains(settings.currencyCode)
            ? Self.currencies : [settings.currencyCode] + Self.currencies
    }

    var body: some View {
        Section {
            AdaptiveRow("Price per kWh") { _ in
                TextField(value: $settings.pricePerKWh,
                          format: .number.precision(.fractionLength(0...4))) {
                    Text(verbatim: "0.30")
                }
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            }
            WrappingPicker("Currency", selection: $settings.currencyCode) {
                ForEach(offered, id: \.self) { code in
                    Text(verbatim: code).tag(code)
                }
            }
        } header: {
            Text("Price")
        }
    }
}

/// Idle and full-load watts used when there is no sensor
struct EnergyEstimateSection: View {
    let target: EnergyTarget
    @ObservedObject var settings: EnergySettings
    let measured: Bool

    private var profile: Binding<EnergyProfile> {
        Binding(get: { settings.profile(target.deployment.id, target.host, cores: target.cores) },
                set: { settings.setProfile($0, target.deployment.id, target.host) })
    }

    private var estimate: PowerEstimate? { settings.estimate(target.deployment.id, target.host) }

    var body: some View {
        Section {
            if let estimate {
                ForEach(Array(estimate.parts.enumerated()), id: \.offset) { _, part in
                    PowerPartRow(part: part)
                }
            }
            wattsField("Idle", value: profile.idleWatts)
            wattsField("Full load", value: profile.peakWatts)
            if settings.isTyped(target.deployment.id, target.host), estimate != nil {
                Button("Use the estimate from the parts") {
                    settings.clearProfile(target.deployment.id, target.host)
                }
            }
        } header: {
            Text("Estimate")
        } footer: {
            Text(footer)
        }
    }

    private var footer: LocalizedStringKey {
        if measured { return "Used only when the sensor is silent. This machine reports its own power." }
        if estimate?.isVirtual == true {
            return "A virtual server: this is its share of the physical host. The hosting provider pays for the electricity."
        }
        if estimate != nil {
            return "Added up from this machine's parts using published processor, disk and power-supply figures. A wall meter gives the exact numbers — enter them above."
        }
        return "Measure the machine with a wall meter once idle and once busy, and enter both — the estimate follows processor load between them."
    }

    private func wattsField(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        AdaptiveRow(title) { _ in
            TextField(value: value, format: .number.precision(.fractionLength(0...1))) {
                Text(verbatim: "0")
            }
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        }
    }
}

/// One estimate part with its idle and full-load watts
private struct PowerPartRow: View {
    let part: PowerPart

    var body: some View {
        LabeledContent {
            Text(verbatim: EnergyFormat.range(part.idleWatts, part.peakWatts))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            Text(verbatim: title)
            if let detail { Text(verbatim: detail) }
        }
    }

    private var title: String {
        switch part.kind {
        case .processor, .singleBoard:
            part.name.isEmpty ? UIL10n.string("Processor") : part.name
        case .memory: UIL10n.string("Memory, %lld GB", part.count)
        case .nvme: UIL10n.string("NVMe drives: %lld", part.count)
        case .ssd: UIL10n.string("SATA SSDs: %lld", part.count)
        case .hdd: UIL10n.string("Hard drives: %lld", part.count)
        case .graphics: UIL10n.string("Graphics cards: %lld", part.count)
        case .serverBoard: UIL10n.string("Server board, fans and management")
        case .desktopBoard: UIL10n.string("Motherboard and fans")
        case .compactBoard: UIL10n.string("Compact board")
        case .virtualShare: UIL10n.string("Share of the host, %lld virtual cores", part.count)
        case .powerSupply: UIL10n.string("Power supply losses")
        }
    }

    private var detail: String? {
        switch part.kind {
        case .processor: part.count > 1 ? UIL10n.string("Processors: %lld", part.count) : UIL10n.string("Processor")
        case .singleBoard: UIL10n.string("Whole board")
        default: nil
        }
    }
}
