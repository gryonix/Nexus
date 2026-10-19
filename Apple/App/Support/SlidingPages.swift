import SwiftUI

/// Pages side by side; the chosen one slides into view
struct SlidingPages<Page: Hashable, Content: View>: View {
    let pages: [Page]
    let selection: Page
    @ViewBuilder let content: (Page) -> Content

    /// The page at rest in view
    @State private var shown: Page?
    /// The page sliding away
    @State private var leaving: Page?
    /// Pages built once and kept alive
    @State private var kept: Set<Page> = []
    @State private var width: CGFloat = 0

    static var motion: Animation { .smooth(duration: 0.38 * SlideSpeed.factor) }

    var body: some View {
        let resting = shown ?? selection
        ZStack {
            ForEach(pages.filter { kept.contains($0) || $0 == selection }, id: \.self) { page in
                content(page)
                    .offset(x: offset(of: page, resting: resting))
                    .opacity(page == resting || page == leaving || page == selection ? 1 : 0)
                    .allowsHitTesting(page == selection)
                    .accessibilityHidden(page != selection)
                    .zIndex(page == selection ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            kept.insert(selection)
            if shown == nil { shown = selection }
        }
        .onChange(of: selection) { old, new in slide(from: old, to: new) }
    }

    /// Pages off to the side wait beyond the edge
    private func offset(of page: Page, resting: Page) -> CGFloat {
        guard page != resting, let index = pages.firstIndex(of: page),
              let rest = pages.firstIndex(of: resting) else { return 0 }
        return index < rest ? -width : width
    }

    private func slide(from old: Page, to new: Page) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            leaving = shown ?? old
            kept.insert(new)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { settle(on: new) }
    }

    /// Slides once the switch has drawn, skipping nothing
    private func settle(on page: Page) {
        #if DEBUG && os(iOS)
        FrameProbe.note("slide start")
        #endif
        withAnimation(Self.motion) {
            shown = page
        } completion: {
            #if DEBUG && os(iOS)
            FrameProbe.note("slide end")
            #endif
            if shown == page { leaving = nil }
        }
    }
}

/// Stretches slides for frame-by-frame checks
enum SlideSpeed {
    static let factor: Double = {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SLIDE_SLOW"]
        return raw.flatMap(Double.init) ?? 1
        #else
        return 1
        #endif
    }()
}
