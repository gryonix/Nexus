import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppAccentChoice: String, CaseIterable, Identifiable {
    /// Whatever the icon is
    case matchesIcon
    /// The shipped `AccentColor` asset
    case app
    case red, orange, yellow, green, teal, purple, pink, graphite
    case black, indigo, brown

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .app: return "App accent"
        case .matchesIcon: return "Match icon"
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

    private static var themeInk: Color { .primary }

    func tint(icon: AppIconChoice) -> Color? {
        switch self {
        case .app: return nil
        case .matchesIcon: return icon == .default ? nil : icon.colour
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .purple: return .purple
        case .pink: return .pink
        case .graphite: return .gray
        case .black: return Self.themeInk
        case .indigo: return .indigo
        case .brown: return .brown
        }
    }

    /// What the dot beside the name is painted in
    func swatch(icon: AppIconChoice) -> Color {
        tint(icon: icon) ?? Color("AccentColor")
    }
}

enum AppAccentSettings {
    static let choiceKey = "appearance.accentChoice"

    /// Reads the choice, migrating the switch this replaced
    static func storedChoice(_ defaults: UserDefaults = .standard) -> AppAccentChoice {
        if let raw = defaults.string(forKey: choiceKey),
           let choice = AppAccentChoice(rawValue: raw) {
            return choice
        }
        let migrated: AppAccentChoice =
            defaults.bool(forKey: AppIconSettings.accentFollowsIconKey) ? .matchesIcon : .app
        defaults.set(migrated.rawValue, forKey: choiceKey)
        return migrated
    }
}

/// The accent list in Appearance
struct AppAccentPicker: View {
    @AppStorage(AppAccentSettings.choiceKey)
    private var choiceRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(AppIconSettings.choiceKey) private var iconRaw = AppIconChoice.default.rawValue
    @State private var expanded = false

    private var choice: AppAccentChoice { AppAccentChoice(rawValue: choiceRaw) ?? .app }
    private var icon: AppIconChoice { AppIconChoice(rawValue: iconRaw) ?? .default }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded },
                set: { newValue in withAnimation(.smooth) { expanded = newValue } }
            )) {
                ForEach(AppAccentChoice.allCases) { candidate in
                    Button {
                        choiceRaw = candidate.rawValue
                    } label: {
                        row(candidate)
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                LabeledContent {
                    HStack(spacing: 8) {
                        dot(choice)
                        Text(choice.title).foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Accent colour")
                }
            }
        } header: {
            InfoSectionHeader("Accent colour", note: "Paints the app's buttons, switches and highlights. Delete and erase stay red whatever is chosen here.")
        }
    }

    private func row(_ candidate: AppAccentChoice) -> some View {
        HStack(spacing: 12) {
            dot(candidate)
            Text(candidate.title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if choice == candidate {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    /// The colour, as a dot before the name
    private func dot(_ candidate: AppAccentChoice) -> some View {
        Circle()
            .fill(candidate.swatch(icon: icon))
            .frame(width: 18, height: 18)
            .overlay {
                Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
            .overlay {
                if candidate == .matchesIcon {
                    Image(systemName: "app.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}
