import SwiftUI

/// Plays the animated splash above the app's first screen, then fades it out.
///
/// The splash covers the screen while it plays, so taps cannot reach the hidden screen
/// underneath. Launch with `--skip-splash` (used by UI tests) to start without it.
struct SplashOverlay: ViewModifier {
    @State private var isVisible = !ProcessInfo.processInfo.arguments.contains("--skip-splash")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .task {
                guard isVisible else { return }
                try? await Task.sleep(for: .seconds(reduceMotion ? 1 : SplashTimeline.duration))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                    isVisible = false
                }
            }
    }
}

extension View {
    /// Covers the view with the animated Travelant splash until it finishes, then fades it out.
    func splashOverlay() -> some View {
        modifier(SplashOverlay())
    }
}
