import SwiftUI

extension View {
    // The card surface itself lives in `GlassCardSurface.swift`.

    @ViewBuilder
    func toolbarGlassButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *), AppChrome.usesGlass {
            menuIndicator(.hidden)
        } else {
            buttonStyle(.bordered)
                .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *), AppChrome.usesGlass {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryActionButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *), AppChrome.usesGlass {
            buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func glassTileButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.bordered)
        #else
        if #available(iOS 26.0, *), AppChrome.usesGlass {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #endif
    }

    @ViewBuilder
    func glassIconButtonStyle() -> some View {
        #if os(macOS)
        macRowButtonStyle()
        #else
        buttonStyle(.borderless)
        #endif
    }

    @ViewBuilder
    func rowActionButtonStyle(inline: Bool = false) -> some View {
        #if os(macOS)
        macRowButtonStyle(fillsRow: !inline)
        #else
        if inline {
            buttonStyle(.borderless)
        } else {
            self
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func macRowButtonStyle(fillsRow: Bool = false) -> some View {
        if fillsRow {
            buttonStyle(RowActionButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        } else {
            buttonStyle(RowActionButtonStyle())
        }
    }

    func formRowButtonStyle() -> some View {
        buttonStyle(RowActionButtonStyle())
    }
    #endif
}

#if os(macOS)
struct RowActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowLabel(configuration: configuration)
    }

    private struct RowLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            configuration.label
                .foregroundStyle(.tint)
                .opacity(isEnabled ? (configuration.isPressed ? 0.4 : 1) : 0.35)
        }
    }
}
#endif
