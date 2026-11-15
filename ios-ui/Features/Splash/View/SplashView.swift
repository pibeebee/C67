import SwiftUI

/// Displays the current app artwork while the app opens.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("SplashGradientMiddle").ignoresSafeArea()
            Image("LaunchArtwork")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .padding(32)
                .accessibilityLabel("Travelant")
        }
    }
}

#if DEBUG
    #Preview("SPLASH") {
        SplashView()
    }
#endif
