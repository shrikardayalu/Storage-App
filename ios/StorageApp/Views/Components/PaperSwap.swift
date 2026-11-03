import SwiftUI

/// A page tossed off the stack and the next one slid on top, tilted like a
/// sheet of paper, for moving between full-screen steps.
struct PaperSwapModifier: ViewModifier {
    /// -1 leaving, 0 resting, 1 arriving.
    let phase: CGFloat

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(phase) * (phase < 0 ? 7 : 4)), anchor: phase < 0 ? .bottomLeading : .bottomTrailing)
            .offset(x: phase * 380, y: abs(phase) * 30)
            .opacity(1 - Double(abs(phase)) * 0.4)
    }
}

extension AnyTransition {
    static var paperSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PaperSwapModifier(phase: 1), identity: PaperSwapModifier(phase: 0)),
            removal: .modifier(active: PaperSwapModifier(phase: -1), identity: PaperSwapModifier(phase: 0))
        )
    }
}
