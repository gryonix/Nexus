import SwiftUI

/// The card material used across the app: real Liquid Glass
struct GlassCardSurface: ViewModifier {
    static let defaultCornerRadius: CGFloat = 16

    var cornerRadius: CGFloat
    var fallback: Color
    var tint: Color?

    @Environment(\.glassCardFloating) private var floating

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), AppChrome.usesGlass {
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    if floating {
                        shape.strokeBorder(.quaternary, lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(floating ? 0.28 : 0),
                        radius: floating ? 26 : 0,
                        x: 0, y: floating ? 14 : 0)
        } else {
            content.background {
                shape
                    .fill(fallback)
                    .overlay { if let tint { shape.fill(tint.opacity(0.12)) } }
                    .overlay { if let tint { shape.strokeBorder(tint.opacity(0.35), lineWidth: 1) } }
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        let base = Glass.regular.interactive()
        guard let tint else { return base }
        return base.tint(tint.opacity(0.10))
    }
}

extension View {
    /// Card surface: the app's glass
    func glassCardBackground(cornerRadius: CGFloat = GlassCardSurface.defaultCornerRadius,
                             fallback: Color,
                             tint: Color? = nil) -> some View {
        modifier(GlassCardSurface(cornerRadius: cornerRadius, fallback: fallback, tint: tint))
    }

    func glassCardFloating(_ floating: Bool = true) -> some View {
        environment(\.glassCardFloating, floating)
    }

    @ViewBuilder
    func glassCardContextMenu<Items: View>(
        @ViewBuilder menuItems: () -> Items
    ) -> some View {
        #if os(iOS)
        contentShape(.contextMenuPreview,
                     RoundedRectangle(cornerRadius: GlassCardSurface.defaultCornerRadius,
                                      style: .continuous))
            .contextMenu(menuItems: menuItems)
        #else
        contextMenu(menuItems: menuItems)
        #endif
    }
}

private struct GlassCardFloatingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glassCardFloating: Bool {
        get { self[GlassCardFloatingKey.self] }
        set { self[GlassCardFloatingKey.self] = newValue }
    }
}

enum GlassPalette {
    static var cardBase: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
