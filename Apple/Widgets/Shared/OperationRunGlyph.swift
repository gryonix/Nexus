#if os(iOS)
import SwiftUI

struct OperationRunGlyph: View {
    let state: OperationActivityAttributes.ContentState
    /// The glyph's square side
    var diameter: CGFloat = 22

    private var outcome: OperationPresentation.Outcome {
        OperationPresentation.outcome(state)
    }

    var body: some View {
        Image(systemName: OperationPresentation.symbol(outcome))
            .font(.system(size: diameter * 0.6, weight: .semibold))
            .foregroundStyle(OperationPresentation.tint(outcome))
        .frame(width: diameter, height: diameter)
    }
}
#endif
