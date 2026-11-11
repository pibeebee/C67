import SwiftUI

/// Screen layout shared by the trip preference questions.
///
/// Shows a `QuestionTitle`, the question's content, an optional bottom action and a native
/// Skip toolbar button. Push it inside a `NavigationStack`; the system back button provides the
/// leading control.
struct QuestionScaffold<Content: View, Footer: View>: View {
    private let title: Text
    private let contentSpacing: CGFloat
    private let skip: () -> Void
    private let content: Content
    private let footer: Footer

    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.skip = skip
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                QuestionTitle(title)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if Footer.self != EmptyView.self {
                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(AppColor.canvas)
            }
        }
        .background(AppColor.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: skip)
            }
        }
        .tint(AppColor.accent)
    }
}

extension QuestionScaffold where Footer == EmptyView {
    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, contentSpacing: contentSpacing, skip: skip, content: content) {
            EmptyView()
        }
    }
}
