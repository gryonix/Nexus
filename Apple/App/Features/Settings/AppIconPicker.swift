import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppIconChoice: String, CaseIterable, Identifiable {
    /// The shipped icon
    case `default`
    case red, orange, yellow, green, teal, purple, pink, graphite
    case black, indigo, brown

    var id: String { rawValue }

    /// The asset name, and what `setAlternateIconName` is given
    var assetName: String? {
        switch self {
        case .default: return nil
        case .red: return "gryonixNexusRed"
        case .orange: return "gryonixNexusOrange"
        case .yellow: return "gryonixNexusYellow"
        case .green: return "gryonixNexusGreen"
        case .teal: return "gryonixNexusTeal"
        case .purple: return "gryonixNexusPurple"
        case .pink: return "gryonixNexusPink"
        case .graphite: return "gryonixNexusGraphite"
        case .black: return "gryonixNexusBlack"
        case .indigo: return "gryonixNexusIndigo"
        case .brown: return "gryonixNexusBrown"
        }
    }

    var previewName: String {
        switch self {
        case .default: return "IconPreviewBlue"
        default: return "IconPreview" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .default: return "Blue"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .teal: return "Teal"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .graphite: return "Graphite"
        case .black: return "Black"
        case .indigo: return "Indigo"
        case .brown: return "Brown"
        }
    }

    var colour: Color {
        switch self {
        case .default: return .blue
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .purple: return .purple
        case .pink: return .pink
        case .graphite: return .gray
        case .black: return .black
        case .indigo: return .indigo
        case .brown: return .brown
        }
    }

    static func current() -> AppIconChoice {
        #if os(iOS)
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.assetName == name } ?? .default
        #else
        return AppIconSettings.storedChoice()
        #endif
    }
}

enum AppIconSettings {
    static let choiceKey = "appearance.iconChoice"
    static let accentFollowsIconKey = "appearance.accentFollowsIcon"

    static func storedChoice(_ defaults: UserDefaults = .standard) -> AppIconChoice {
        AppIconChoice(rawValue: defaults.string(forKey: choiceKey) ?? "") ?? .default
    }

    static func store(_ choice: AppIconChoice, in defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: choiceKey)
    }

    #if os(iOS)
    static func reconcileWithSystem(_ defaults: UserDefaults = .standard) {
        store(AppIconChoice.current(), in: defaults)
    }
    #endif

    #if os(iOS)
    /// Repaints the UIKit half of the app
    @MainActor
    static func applyWindowTint(_ colour: UIColor?) {
        let resolved = colour ?? UIColor(named: "AccentColor")
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = resolved
            }
        }
    }
    #endif

    #if os(macOS)
    @MainActor
    static func applyDockIcon(_ choice: AppIconChoice = storedChoice()) {
        NSApplication.shared.applicationIconImage = choice == .default ? nil : dockIcon(for: choice)
    }

    @MainActor
    static func dockIcon(for choice: AppIconChoice) -> NSImage? {
        guard let artwork = NSImage(named: choice.previewName) else { return nil }
        let side: CGFloat = 512
        let inset = side * Self.macGridMargin
        let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let radius = tile.width * 0.2237

        let rounded = NSImage(size: tile.size)
        rounded.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: tile.size),
                     xRadius: radius, yRadius: radius).fill()
        artwork.draw(in: NSRect(origin: .zero, size: tile.size), from: .zero,
                     operation: .sourceAtop, fraction: 1)
        rounded.unlockFocus()

        let icon = NSImage(size: NSSize(width: side, height: side))
        icon.lockFocus()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
        shadow.shadowBlurRadius = side * 0.02
        shadow.set()
        rounded.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
        icon.unlockFocus()
        return icon
    }

    /// The margin of Apple's Mac icon grid
    static let macGridMargin: CGFloat = 100 / 1024

    #endif
}

struct AppAccentTint: ViewModifier {
    @AppStorage(AppAccentSettings.choiceKey)
    private var accentRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(AppIconSettings.choiceKey) private var choiceRaw = AppIconChoice.default.rawValue

    private var choice: AppIconChoice { AppIconChoice(rawValue: choiceRaw) ?? .default }
    private var accent: AppAccentChoice { AppAccentChoice(rawValue: accentRaw) ?? .app }
    private var tint: Color? { accent.tint(icon: choice) }

    func body(content: Content) -> some View {
        content
            .tint(tint)
            #if os(iOS)
            .task(id: "\(accentRaw)-\(choiceRaw)") {
                AppIconSettings.applyWindowTint(tint.map(UIColor.init))
            }
            #endif
    }
}

extension View {
    func appAccentTint() -> some View { modifier(AppAccentTint()) }
}

/// The grid of icons in Appearance
struct AppIconPicker: View {
    @State private var selection = AppIconChoice.current()
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 16)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        apply(choice)
                    } label: {
                        icon(choice)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            if let failure {
                Text(failure).foregroundStyle(.red)
            }
        } header: {
            InfoSectionHeader("App icon") {
                #if os(iOS)
                Text("The icon on the home screen. iOS confirms the change itself.")
                #else
                Text("The icon in the Dock and the app switcher. macOS gives an app no way to change its own icon in Finder, so that one stays as it shipped.")
                #endif
                Text("The app's own accent colour is chosen separately, below.")
            }
        }
        #if DEBUG && os(iOS)
        .task {
            guard let name = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SET_ICON"],
                  let choice = AppIconChoice.allCases.first(where: { $0.assetName == name }) else { return }
            try? await Task.sleep(for: .seconds(2))
            apply(choice)
        }
        #endif
    }

    private func icon(_ choice: AppIconChoice) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let image = Self.preview(choice) {
                    image.resizable()
                } else {
                    choice.colour
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selection == choice ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: selection == choice ? 3 : 1)
            }
            Text(choice.title)
                .font(.caption2)
                .foregroundStyle(selection == choice ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selection else { return }
        let previous = selection
        selection = choice
        AppIconSettings.store(choice)
        failure = nil
        #if os(iOS)
        UIApplication.shared.setAlternateIconName(choice.assetName) { error in
            guard let error else { return }
            Task { @MainActor in
                selection = previous
                AppIconSettings.store(previous)
                failure = error.localizedDescription
            }
        }
        #else
        _ = previous
        AppIconSettings.applyDockIcon(choice)
        #endif
    }

    /// The flat artwork behind a swatch
    private static func preview(_ choice: AppIconChoice) -> Image? {
        #if os(iOS)
        UIImage(named: choice.previewName).map(Image.init(uiImage:))
        #else
        NSImage(named: choice.previewName).map(Image.init(nsImage:))
        #endif
    }
}
