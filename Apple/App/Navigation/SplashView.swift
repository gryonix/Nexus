import SwiftUI

struct SplashView: View {
    var colour: Color
    var opacity: Double = 1

    var body: some View {
        ZStack {
            Color.splashBackground
            ZStack {
                layer("SplashLayerServer").foregroundStyle(colour)
                layer("SplashLayerHalo").foregroundStyle(Color.splashBackground)
                layer("SplashLayerGear").foregroundStyle(colour)
            }
            .frame(width: 240, height: 240)
        }
        .opacity(opacity)
        .ignoresSafeArea()
    }

    private func layer(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

extension Color {
    static let splashBackground = Color("LaunchBackground")
}

struct SplashGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true
    @State private var isContentMounted = false
    @State private var isContentReady = false
    @State private var colour = AppIconChoice.default.colour
    @State private var opacity: Double = 1

    private static var fade: Duration { .milliseconds(500) }
    private static var settle: Duration { .milliseconds(160) }
    private static var beforeContent: Duration { .milliseconds(500) }
    private static var floor: Duration { .milliseconds(200) }
    private static var ceiling: Duration { .seconds(4) }

    var body: some View {
        ZStack {
            if isContentMounted {
                content()
                    .onAppear { isContentReady = true }
            }
            if isVisible {
                SplashView(colour: colour, opacity: opacity)
            }
        }
        .task {
            #if os(iOS)
            AppIconSettings.reconcileWithSystem()
            #else
            AppIconSettings.applyDockIcon()
            #endif
            let chosen = AppIconSettings.storedChoice().colour
            if !reduceMotion, chosen != AppIconChoice.default.colour {
                withAnimation(.easeInOut(duration: 0.45)) { colour = chosen }
                try? await Task.sleep(for: Self.beforeContent)
            } else {
                colour = chosen
            }
            isContentMounted = true

            try? await Task.sleep(for: Self.floor)
            await waitForContent()
            try? await Task.sleep(for: Self.settle)
            withAnimation(.easeInOut(duration: 0.5)) { opacity = 0 }
            try? await Task.sleep(for: Self.fade)
            isVisible = false
        }
    }

    private func waitForContent() async {
        #if DEBUG
        if let seconds = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SPLASH_HOLD"],
           let value = Double(seconds) {
            try? await Task.sleep(for: .seconds(value))
            return
        }
        #endif
        let step = Duration.milliseconds(40)
        var waited = Duration.zero
        while !isContentReady && waited < Self.ceiling {
            try? await Task.sleep(for: step)
            waited += step
        }
    }
}
