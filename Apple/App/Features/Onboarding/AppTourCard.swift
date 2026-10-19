import SwiftUI

/// One step's explanation and its buttons
struct AppTourCard: View {
    let step: AppTourStep
    @ObservedObject var bars: TabBarSettings
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onConfigure: () -> Void
    /// Draws its own panel; off inside a popover
    var framed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: step.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: step)
                Spacer()
                if step != .finish {
                    Button("Skip", action: onSkip)
                        .font(.subheadline)
                        .accessibilityIdentifier("tour.skip")
                }
            }
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }.scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
        .lineLimit(nil)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(20)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("tour.card")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title).font(.title3.bold())
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var extra: some View {
        switch step {
        case .tabBarStyle:
            styleRow("Bottom tab bar", selection: $bars.barStyle, identifier: "tour.barStyle")
        case .stripStyle:
            styleRow("Server section strip", selection: $bars.sectionStripStyle, identifier: "tour.stripStyle")
        default: EmptyView()
        }
    }

    private func styleRow(_ title: LocalizedStringKey, selection: Binding<BarStyle>,
                          identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color.secondary)
            Picker(title, selection: selection) {
                ForEach(BarStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder private var footer: some View {
        if step == .finish {
            VStack(spacing: 12) {
                HStack {
                    AppTourDots(current: step)
                    Spacer()
                    Button("Back", action: onBack)
                    .lineLimit(1).fixedSize()
                    .accessibilityIdentifier("tour.back")
                }
                HStack(spacing: 10) {
                    Button(action: onConfigure) {
                        Text("Set up a server").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                    }
                    .secondaryActionButtonStyle()
                    Button(action: onNext) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .prominentActionButtonStyle()
                    .accessibilityIdentifier("tour.next")
                }
                .controlSize(.large)
            }
            .font(.subheadline.weight(.semibold))
        } else {
            HStack(spacing: 12) {
                AppTourDots(current: step)
                Spacer()
                if step != AppTourStep.tour.first {
                    Button("Back", action: onBack)
                    .lineLimit(1).fixedSize()
                    .accessibilityIdentifier("tour.back")
                }
                Button("Next", action: onNext)
                    .lineLimit(1).fixedSize()
                    .prominentActionButtonStyle()
                    .accessibilityIdentifier("tour.next")
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

/// Which step of how many
struct AppTourDots: View {
    let current: AppTourStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTourStep.tour) { step in
                Capsule()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: step == current ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }
}
