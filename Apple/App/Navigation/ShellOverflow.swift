import SwiftUI

@MainActor
final class ShellOverflow: ObservableObject {
    static let shared = ShellOverflow()

    @Published var sections: [AppTab] = []
    @Published var current: AppTab?

    @Published var screensOwningBottom = 0

    private init() {}
}

struct OwnsBottomEdge: ViewModifier {
    @ObservedObject private var overflow = ShellOverflow.shared

    func body(content: Content) -> some View {
        content
            .onAppear { overflow.screensOwningBottom += 1 }
            .onDisappear { overflow.screensOwningBottom = max(0, overflow.screensOwningBottom - 1) }
    }
}

extension View {
    func ownsBottomEdge() -> some View { modifier(OwnsBottomEdge()) }
}

/// One order on every section: own actions, process, then "…" last
struct SectionToolbar<Actions: View, MenuItems: View>: ViewModifier {
    let tab: AppTab
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let menuItems: () -> MenuItems
    @ObservedObject private var overflow = ShellOverflow.shared

    private var hasSections: Bool { overflow.current == tab && overflow.sections.count > 0 }
    private var hasOwnItems: Bool { MenuItems.self != EmptyView.self }

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    actions()
                    RunningProcessButton()
                    if hasOwnItems || hasSections { menu }
                }
            }
    }

    private var menu: some View {
        Menu {
            menuItems()
            if hasSections {
                if hasOwnItems { Divider() }
                sectionItems
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .toolbarGlassButtonStyle()
    }

    @ViewBuilder private var sectionItems: some View {
        ForEach(overflow.sections) { section in
            Button {
                overflow.current = section
            } label: {
                Label { Text(section.title) } icon: { section.icon }
            }
            .disabled(section == tab)
        }
        Divider()
        Button {
            overflow.current = nil
        } label: {
            Label("All sections", systemImage: "list.bullet")
        }
    }
}

extension View {
    func sectionToolbar(_ tab: AppTab) -> some View {
        modifier(SectionToolbar(tab: tab, actions: { EmptyView() }, menuItems: { EmptyView() }))
    }

    func sectionToolbar<MenuItems: View>(
        _ tab: AppTab, @ViewBuilder menu: @escaping () -> MenuItems
    ) -> some View {
        modifier(SectionToolbar(tab: tab, actions: { EmptyView() }, menuItems: menu))
    }

    func sectionToolbar<Actions: View, MenuItems: View>(
        _ tab: AppTab,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder menu: @escaping () -> MenuItems
    ) -> some View {
        modifier(SectionToolbar(tab: tab, actions: actions, menuItems: menu))
    }
}
