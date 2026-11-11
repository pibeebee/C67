#if DEBUG
import SwiftUI

/// Pushes a question onto a navigation stack in previews, so the native back button and
/// Skip toolbar look as they do in the app.
struct PreferenceQuestionPreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            AppColor.canvas
                .ignoresSafeArea()
                .navigationDestination(isPresented: .constant(true)) {
                    content
                }
        }
    }
}
#endif
