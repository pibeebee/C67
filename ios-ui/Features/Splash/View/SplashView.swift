import SwiftUI

/// Animated Travelant splash, matched to the brand video `Travelant-Splash-iPhone17.mp4`:
/// the orange ball draws the pin, hops into its center and the antennae pop in. Then a small
/// ball relays down to the italic wordmark, which springs up letter by letter as it rolls past,
/// and the tagline fades in.
///
/// With Reduce Motion on, it shows the finished logo without movement.
struct SplashView: View {
    /// When the animation started. Defaults to now; pass a fixed date to resume or replay.
    var startDate = Date.now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            SplashFrameView(frame: reduceMotion
                ? SplashTimeline.finalFrame
                : SplashTimeline.frame(at: context.date.timeIntervalSince(startDate)))
        }
    }
}

#if DEBUG
    /// Replays the animation every time the preview is tapped.
    private struct SplashReplayPreview: View {
        @State private var startDate = Date.now

        var body: some View {
            SplashView(startDate: startDate)
                .onTapGesture { startDate = .now }
        }
    }

    #Preview("SPLASH · Animated (tap to replay)") {
        SplashReplayPreview()
    }
#endif
