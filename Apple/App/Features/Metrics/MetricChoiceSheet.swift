import SwiftUI

struct MetricChoiceSheet: View {
    let offered: [HistoryMetric]
    /// What the chart plots now
    let selected: [HistoryMetric]
    /// The new set, in catalog order
    let onChoose: ([HistoryMetric]) -> Void

    @State private var current: Set<HistoryMetric>
    @Environment(\.dismiss) private var dismiss

    init(offered: [HistoryMetric], selected: [HistoryMetric],
         onChoose: @escaping ([HistoryMetric]) -> Void) {
        self.offered = offered
        self.selected = selected
        self.onChoose = onChoose
        _current = State(initialValue: Set(selected))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(offered) { metric in
                        Button {
                            current = HistoryMetric.toggling(metric, in: current)
                        } label: {
                            row(metric)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    InfoSectionHeader("Metrics", note: "CPU, memory and disk can be shown together — they share one 0–100 % axis. Anything else is plotted on its own.")
                }
            }
            .navigationTitle("Metric")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            let chosen = offered.filter(current.contains)
            guard !chosen.isEmpty, chosen != selected else { return }
            onChoose(chosen)
        }
        #if os(iOS)
        .phoneSheetDetents([.medium])
        #else
        .frame(minWidth: 320, minHeight: 320)
        #endif
    }

    private func row(_ metric: HistoryMetric) -> some View {
        HStack(spacing: 12) {
            Image(systemName: metric.systemImage)
                .foregroundStyle(metric.tint)
                .frame(width: 24)
            Text(metric.title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if current.contains(metric) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

struct MetricPanelActionsSheet: View {
    let title: String
    let subtitle: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    private enum Action { case edit, delete }

    @State private var pending: Action?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        pending = .edit
                        dismiss()
                    } label: {
                        row("Edit", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        pending = .delete
                        dismiss()
                    } label: {
                        row("Delete", systemImage: "trash", destructive: true)
                    }
                    .buttonStyle(.plain)
                    .dangerTint()
                } header: {
                    Text(verbatim: subtitle)
                }
            }
            .navigationTitle(Text(verbatim: title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pending = nil
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            switch pending {
            case .edit: onEdit()
            case .delete: onDelete()
            case nil: break
            }
            pending = nil
        }
        #if os(iOS)
        .phoneSheetDetents([.height(240)])
        #else
        .frame(minWidth: 320, minHeight: 220)
        #endif
    }

    private func row(_ title: LocalizedStringKey, systemImage: String,
                     destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.accentColor))
                .frame(width: 24)
            Text(title)
                .foregroundStyle(destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}
