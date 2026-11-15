import SwiftUI

/// A toolbar label; the TV bar fits only the icon
struct ToolbarIcon: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    #if os(tvOS)
    @Environment(\.tvHeaderLabels) private var labelled
    #endif

    var body: some View {
        #if os(tvOS)
        if labelled {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .accessibilityLabel(Text(title))
        }
        #else
        Label(title, systemImage: systemImage)
        #endif
    }
}

extension View {
    /// Screen title; the TV shows it small in the bar
    func screenTitle(_ title: LocalizedStringKey) -> some View {
        modifier(ScreenTitle(title: Text(title)))
    }

    func screenTitle(_ title: Text) -> some View {
        modifier(ScreenTitle(title: title))
    }

    @_disfavoredOverload
    func screenTitle<S: StringProtocol>(_ title: S) -> some View {
        modifier(ScreenTitle(title: Text(verbatim: String(title))))
    }
}

extension View {
    /// Main screen buttons; beside the title on the TV
    @ViewBuilder
    func screenActions<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        #if os(tvOS)
        tvHeaderActions(actions)
        #else
        toolbar { ToolbarItemGroup(placement: .primaryAction) { actions() } }
        #endif
    }
}

extension View {
    /// Row icon column; wider on the TV's larger symbols
    @ViewBuilder func rowIconFrame(_ width: CGFloat) -> some View {
        #if os(tvOS)
        frame(width: width * 2).padding(.trailing, 8)
        #else
        frame(width: width)
        #endif
    }
}

private struct ScreenTitle: ViewModifier {
    let title: Text
    #if os(tvOS)
    @State private var width: CGFloat = .infinity
    @Environment(\.tvHeaderActions) private var actions
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            heading
            content
                .environment(\.tvHeaderActions, nil)
                .padding(.horizontal, isSheet ? TVSpacing.rowInset : TVSpacing.screenInset)
                .scrollClipDisabled()
                .mask { TVContentMask(fades: !isSheet) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .toolbar {
            // Empty title keeps the system title out of the bar
            ToolbarItem(placement: .principal) { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
        #else
        content.navigationTitle(title)
        #endif
    }

    #if os(tvOS)
    private var isSheet: Bool { width < TVSpacing.sheetWidth }

    /// Title and screen buttons above the content
    @ViewBuilder private var heading: some View {
        if isSheet {
            title.font(.title3.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        } else {
            ZStack {
                title.font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 360)
                if let actions {
                    HStack(spacing: 24) {
                        Spacer(minLength: 0)
                        actions
                    }
                    .environment(\.tvHeaderLabels, true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.horizontal, TVSpacing.screenInset)
            .padding(.bottom, 16)
            .focusSection()
        }
    }
    #endif
}

#if os(tvOS)
/// Fades out content scrolled under the heading
private struct TVContentMask: View {
    let fades: Bool

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [fades ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
            Color.black
        }
        .padding(.top, fades ? 0 : -60)
        .padding(.horizontal, -80)
        .padding(.bottom, -120)
    }
}

private struct TVHeaderActionsKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

private struct TVHeaderLabelsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The screen's buttons, shown by its title on the TV
    var tvHeaderActions: AnyView? {
        get { self[TVHeaderActionsKey.self] }
        set { self[TVHeaderActionsKey.self] = newValue }
    }

    /// Toolbar icons in the TV heading carry their titles
    var tvHeaderLabels: Bool {
        get { self[TVHeaderLabelsKey.self] }
        set { self[TVHeaderLabelsKey.self] = newValue }
    }
}

extension View {
    /// Buttons for the TV heading; apply outside `screenTitle`
    func tvHeaderActions<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        environment(\.tvHeaderActions, AnyView(actions()))
    }
}
#endif

#if os(tvOS)
/// Icon and title with room between, for TV distance
struct TVRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TVSpacing.iconGap) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}

/// Room a focused, enlarged row needs inside a sheet
enum TVSpacing {
    static let iconGap: CGFloat = 20
    static let rowInset: CGFloat = 32
    /// Keeps a focused row clear of the screen edge
    static let screenInset: CGFloat = 48
    /// Narrower than this is a sheet, not a screen
    static let sheetWidth: CGFloat = 1200
}
#endif
