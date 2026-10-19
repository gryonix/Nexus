import ServerControl
import SwiftUI

/// Interval and time of a schedule that is on
struct ScheduleFields: View {
    @Binding var schedule: CommandCatalog.Backups.Schedule

    @State private var unit: Unit
    @State private var interval: Int
    @State private var hour: Int
    @State private var minute: Int

    enum Unit: Hashable { case hours, days }

    /// What switching a schedule on starts from
    static let defaultOn = CommandCatalog.Backups.Schedule.days(count: 1, hour: 4, minute: 0)

    init(schedule: Binding<CommandCatalog.Backups.Schedule>) {
        _schedule = schedule
        switch schedule.wrappedValue {
        case .hours(let count, let minute):
            _unit = State(initialValue: .hours); _interval = State(initialValue: count)
            _hour = State(initialValue: 4); _minute = State(initialValue: minute)
        case .days(let count, let hour, let minute):
            _unit = State(initialValue: .days); _interval = State(initialValue: count)
            _hour = State(initialValue: hour); _minute = State(initialValue: minute)
        case .off:
            _unit = State(initialValue: .days); _interval = State(initialValue: 1)
            _hour = State(initialValue: 4); _minute = State(initialValue: 0)
        }
    }

    private var composed: CommandCatalog.Backups.Schedule {
        switch unit {
        case .hours: return .hours(count: interval, minute: minute)
        case .days: return .days(count: interval, hour: hour, minute: minute)
        }
    }

    var body: some View {
        Picker("Repeat", selection: $unit) {
            Text("Hours").tag(Unit.hours)
            Text("Days").tag(Unit.days)
        }
        .pickerStyle(.segmented)
        .onChange(of: unit) { _, _ in
            interval = min(interval, unit == .hours ? 23 : 28)
            schedule = composed
        }
        Stepper(value: $interval, in: 1...(unit == .hours ? 23 : 28)) {
            HStack {
                Text(unit == .hours ? "Every N hours" : "Every N days")
                Spacer()
                Text(verbatim: "\(interval)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .onChange(of: interval) { _, _ in schedule = composed }
        DatePicker(unit == .hours ? "At minute" : "At time", selection: time,
                   displayedComponents: .hourAndMinute)
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = parts.hour ?? hour
                minute = parts.minute ?? minute
                schedule = composed
            })
    }

    /// The closed row's short form
    static func summary(_ schedule: CommandCatalog.Backups.Schedule) -> String {
        switch schedule {
        case .off:
            return UIL10n.string("Off")
        case .hours(let count, let minute):
            return UIL10n.string("Every %@ h", "\(count)") + String(format: " · :%02d", minute)
        case .days(let count, let hour, let minute):
            return UIL10n.string("Every %@ d", "\(count)") + String(format: " · %02d:%02d", hour, minute)
        }
    }
}
