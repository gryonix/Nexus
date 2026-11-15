#if !os(tvOS)
import ServerControl
import SwiftUI

/// Time zone, host name and time sync of one machine
struct SystemSettingsRows: View {
    @ObservedObject var model: SystemSettingsModel
    let host: SSHHostID

    var body: some View {
        if let value = model.settings[host] {
            NavigationLink {
                TimeZonePage(model: model, host: host)
            } label: {
                LabeledContent("Time zone") { Text(verbatim: value.timeZone) }
            }
            NavigationLink {
                HostNamePage(model: model, host: host)
            } label: {
                LabeledContent("Host name") { Text(verbatim: value.hostName) }
            }
            syncToggle(value)
            if let error = model.errors[host] {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func syncToggle(_ value: HostSystemSettings) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Sync time automatically", isOn: Binding(
                get: { value.ntpEnabled },
                set: { on in Task { await model.setTimeSync(on, host: host) } }))
                .disabled(model.busy.contains(host))
            if value.ntpEnabled {
                Text(value.ntpSynchronized ? "The clock is in sync." : "The clock is not in sync yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Searchable list of the time zones a machine knows
private struct TimeZonePage: View {
    @ObservedObject var model: SystemSettingsModel
    let host: SSHHostID
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var zones: [String] {
        let all = model.settings[host]?.timeZones ?? []
        let query = search.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(zones, id: \.self) { zone in
            Button {
                Task {
                    await model.setTimeZone(zone, host: host)
                    dismiss()
                }
            } label: {
                HStack {
                    Text(verbatim: zone)
                    Spacer()
                    if zone == model.settings[host]?.timeZone {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .screenTitle(Text("Time zone"))
        .searchable(text: $search, prompt: Text("Search time zones"))
        .disabled(model.busy.contains(host))
    }
}

/// Edit one machine's host name
private struct HostNamePage: View {
    @ObservedObject var model: SystemSettingsModel
    let host: SSHHostID
    @State private var draft = ""
    @StateObject private var edits = PendingRowEdits()
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool { HostNameRules.isValid(draft) }

    /// Tells the bar whether the name waits
    private func offerEdit() {
        let field = $draft
        let saved = model.settings[host]?.hostName ?? ""
        let edit = PendingRowEdits.Edit(
            id: "host-name", text: .save,
            apply: { [model, host, dismiss] in
                await model.setHostName(field.wrappedValue, host: host)
                dismiss()
                return true
            },
            revert: { field.wrappedValue = saved })
        edits.offer(edit, changed: PendingRules.hostName(draft, saved: saved))
    }

    var body: some View {
        CardList {
            Section {
                TextField("Host name", text: $draft)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                Text(draft.isEmpty || valid
                     ? "Lowercase letters, digits and hyphens, up to 63 characters."
                     : "This is not a valid host name.")
            }
        }
        .screenTitle(Text("Host name"))
        .onAppear { draft = model.settings[host]?.hostName ?? "" }
        .onChange(of: draft) { offerEdit() }
        .pendingRowEdits(edits)
    }
}

/// The reboot timer of one machine
struct RebootScheduleRows: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    let edits: PendingRowEdits
    @State private var draft: RebootSchedule?

    private var saved: RebootSchedule? { model.statuses[host]?.rebootSchedule }

    /// Tells the bar whether the schedule waits
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "reboot-schedule-\(host)", text: .schedule,
            apply: { [model, host] in
                if let asked = field.wrappedValue { await model.setRebootSchedule(asked, host: host) }
                field.wrappedValue = nil
                return true
            },
            revert: { field.wrappedValue = nil })
        edits.offer(edit, changed: PendingRules.waits(draft, saved: saved))
    }

    var body: some View {
        if let saved {
            let current = draft ?? saved
            Picker("Restart automatically", selection: Binding(get: { Mode(current) }, set: { draft = $0.schedule(from: current) })) {
                Text("Off").tag(Mode.off)
                Text("Daily").tag(Mode.daily)
                Text("Weekly").tag(Mode.weekly)
            }
            .disabled(model.busy.contains(host))
            .onChange(of: draft) { offerEdit() }
            if case .weekly(let weekday, _, _) = current {
                Picker("Day", selection: Binding(get: { weekday }, set: { draft = $0.weekly(from: current) })) {
                    ForEach(1...7, id: \.self) { Text(verbatim: Self.dayName($0)).tag($0) }
                }
            }
            if current != .off {
                DatePicker("At time", selection: time(current), displayedComponents: .hourAndMinute)
            }
        }
    }

    private func time(_ schedule: RebootSchedule) -> Binding<Date> {
        Binding(
            get: {
                let parts = schedule.clock
                return Calendar.current.date(from: DateComponents(hour: parts.hour, minute: parts.minute)) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft = schedule.at(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            })
    }

    /// Monday is 1 and Sunday is 7
    static func dayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday % 7]
    }

    private enum Mode: Hashable {
        case off, daily, weekly

        init(_ schedule: RebootSchedule) {
            switch schedule {
            case .off: self = .off
            case .daily: self = .daily
            case .weekly: self = .weekly
            }
        }

        func schedule(from current: RebootSchedule) -> RebootSchedule {
            let clock = current == .off ? (hour: 4, minute: 0) : current.clock
            switch self {
            case .off: return .off
            case .daily: return .daily(hour: clock.hour, minute: clock.minute)
            case .weekly: return .weekly(weekday: 7, hour: clock.hour, minute: clock.minute)
            }
        }
    }
}

private extension Int {
    func weekly(from current: RebootSchedule) -> RebootSchedule {
        .weekly(weekday: self, hour: current.clock.hour, minute: current.clock.minute)
    }
}

extension RebootSchedule {
    /// The time of day, 04:00 when off
    var clock: (hour: Int, minute: Int) {
        switch self {
        case .off: return (4, 0)
        case .daily(let hour, let minute), .weekly(_, let hour, let minute): return (hour, minute)
        }
    }

    func at(hour: Int, minute: Int) -> RebootSchedule {
        switch self {
        case .off: return .off
        case .daily: return .daily(hour: hour, minute: minute)
        case .weekly(let weekday, _, _): return .weekly(weekday: weekday, hour: hour, minute: minute)
        }
    }
}
#endif
