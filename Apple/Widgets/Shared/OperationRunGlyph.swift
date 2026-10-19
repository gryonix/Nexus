#if os(iOS)
import SwiftUI

struct OperationRunGlyph: View {
    let state: OperationActivityAttributes.ContentState
    /// The whole glyph, ring included
    var diameter: CGFloat = 22

    private var outcome: OperationPresentation.Outcome {
        OperationPresentation.outcome(state)
    }

    var body: some View {
        ZStack {
            if let fraction = OperationPresentation.barValue(state) {
                Circle()
                    .stroke(OperationPresentation.tint(outcome).opacity(0.25),
                            lineWidth: Self.stroke)
                    .padding(Self.stroke / 2)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(OperationPresentation.tint(outcome),
                            style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                    .padding(Self.stroke / 2)
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: OperationPresentation.symbol(outcome))
                .font(.system(size: diameter * 0.5, weight: .semibold))
                .foregroundStyle(OperationPresentation.tint(outcome))
        }
        .frame(width: diameter, height: diameter)
    }

    private static let stroke: CGFloat = 2.5
}
#endif
