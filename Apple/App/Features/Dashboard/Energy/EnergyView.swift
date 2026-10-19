import Charts
import ServerControl
import SwiftUI

/// Power now, energy per day and month, and cost
struct EnergyView: View {
    @StateObject private var model: EnergyViewModel
    @ObservedObject private var settings = EnergySettings.shared

    init(target: EnergyTarget) {
        _model = StateObject(wrappedValue: EnergyViewModel(target: target))
    }

    var body: some View {
        CardList {
            EnergyNowSection(point: model.latest, measured: model.isMeasured)
            EnergyCostSection(model: model, settings: settings)
            EnergyDaysSection(days: model.days)
            EnergyPriceSection(settings: settings)
            EnergyEstimateSection(target: model.target, settings: settings, measured: model.isMeasured)
        }
        .navigationTitle("Energy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .refreshableWithShortcut { await model.load() }
        .onDisappear { model.teardown() }
        .onChange(of: settings.pricePerKWh) { model.objectWillChange.send() }
    }
}

private struct EnergyNowSection: View {
    let point: MetricsHistoryPoint?
    let measured: Bool

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text(verbatim: point?.powerWatts.map(EnergyFormat.watts) ?? "—")
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Spacer()
            }
            Text(EnergySourceText.describe(point?.powerSource))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Now")
        }
    }
}

enum EnergySourceText {
    static func describe(_ source: String?) -> LocalizedStringKey {
        switch source {
        case "rapl+estimate": return "The processor measures itself; memory, disks, the board and the power supply's losses are added from the machine's parts."
        case "hwmon+estimate": return "A board sensor measures the processor; disks, memory, the board and the power supply's losses are added from the machine's parts."
        case "pi+estimate": return "The Raspberry Pi's power chip measures the board; disks and the power supply's losses are added from the machine's parts."
        case "rapl": return "Measured by the processor — CPU and memory only, not disks or the power supply."
        case "hwmon": return "Measured by a sensor on the board."
        case "ipmi": return "Measured by the server's management controller — the whole machine."
        case "ups": return "Measured by the UPS — everything plugged into it."
        case "pi": return "Measured by the Raspberry Pi's power chip."
        default: return "Estimated from the machine's parts and processor load: it has no power sensor."
        }
    }
}

private struct EnergyCostSection: View {
    @ObservedObject var model: EnergyViewModel
    let settings: EnergySettings

    var body: some View {
        Section {
            row("Today", model.today)
            row("This month so far", model.monthSoFar)
            row("Forecast for the month", model.monthForecast)
            if let last = model.lastMonth { row("Last month", last) }
        } header: {
            InfoSectionHeader("Energy and cost", note: "Energy is the power history added up over time. The price per kilowatt-hour is set below.")
        }
    }

    private func row(_ title: LocalizedStringKey, _ kilowattHours: Double) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: settings.cost(kilowattHours)).monospacedDigit()
                Text(verbatim: EnergyFormat.kilowattHours(kilowattHours))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct EnergyDaysSection: View {
    let days: [(date: Date, kilowattHours: Double)]

    var body: some View {
        Section {
            if days.allSatisfy({ $0.kilowattHours == 0 }) {
                Text("No history yet").foregroundStyle(.secondary)
            } else {
                Chart(days, id: \.date) { day in
                    BarMark(x: .value("Date", day.date, unit: .day),
                            y: .value("kWh", day.kilowattHours))
                        .foregroundStyle(.yellow.gradient)
                }
                .chartYAxisLabel(UIL10n.string("kWh"))
                .frame(height: 180)
            }
        } header: {
            Text("Last 30 days")
        }
    }
}
