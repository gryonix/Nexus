import SwiftUI

/// The sections that did not fit on the tab bar
struct MoreSectionsView: View {
    let sections: [AppTab]
    let onSelect: (AppTab) -> Void

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    ForEach(sections) { section in
                        Button {
                            onSelect(section)
                        } label: {
                            row(section)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    InfoSectionHeader("More sections", note: "The bar holds five sections; these are the rest. Which ones the bar carries, and in what order, is set in Settings › Sections.")
                }
            }
            .navigationTitle("More")
            .raisedNavigationTitle()
        }
    }

    private func row(_ section: AppTab) -> some View {
        HStack(spacing: 12) {
            section.icon
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(section.title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
