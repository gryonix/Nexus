import ServiceCatalog
import SwiftUI

struct ServicePickerSheet: View {
    let category: ServiceCategory
    /// Which members this deployment can actually run
    let scope: DeploymentScope
    /// What is ticked already, so an add-on sees its hub
    let selected: Set<ServiceID>
    let binding: (ServiceID) -> Binding<Bool>
    let note: (ServiceID) -> LocalizedStringKey?

    @Environment(\.dismiss) private var dismiss

    private var services: [any ManagedService] {
        ServiceRegistry.services(in: category, scope: scope, selected: selected)
    }

    /// Several at once, or exactly one?
    private var allowsSeveral: Bool { category.selection != .exclusive }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(services, id: \.id) { service in
                        row(service)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(sheetBackground)
            .navigationTitle(LocalizedStringKey(category.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(allowsSeveral
                     ? "Pick as many as you need — they run side by side."
                     : "Only one of these can run on a server: they want the same ports.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    /// One product
    private func row(_ service: any ManagedService) -> some View {
        let isOn = binding(service.id)
        return Button {
            if allowsSeveral || !isOn.wrappedValue {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: service.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: service.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if service.id != .gitlab {
                        Text("Needs about \(Self.memoryText(service.resources))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = note(service.id) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isOn.wrappedValue
                      ? (allowsSeveral ? "checkmark.circle.fill" : "largecircle.fill.circle")
                      : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(.tint)
                                                       : AnyShapeStyle(.secondary))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCardBackground(fallback: GlassPalette.cardBase)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private static func memoryText(_ resources: ServiceResources) -> String {
        resources.memoryMB >= 1024
            ? "\(Int((Double(resources.memoryMB) / 1024).rounded(.up))) GB"
            : "\(resources.memoryMB) MB"
    }

    private var sheetBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color.clear
        #endif
    }
}

struct ServiceCategoryLabel: View {
    let category: ServiceCategory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CategoryIcon(category: category)
                .foregroundStyle(.tint)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(category.title))
                if !category.summary.isEmpty {
                    Text(LocalizedStringKey(category.summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
