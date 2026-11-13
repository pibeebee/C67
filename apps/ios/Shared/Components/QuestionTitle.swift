import SwiftUI

/// Bold, leading-aligned question heading with optional accent-colored words.
///
/// Build highlighted titles with text interpolation so each phrase stays one localizable string:
/// `QuestionTitle(Text("\(QuestionTitle.highlight("Popular")) spots?"))`.
struct QuestionTitle: View {
    private let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(AppFont.title1Bold)
            .foregroundStyle(AppColor.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Returns a word or phrase in the accent color for use inside a `QuestionTitle`.
    static func highlight(_ resource: LocalizedStringResource) -> Text {
        Text(resource).foregroundStyle(AppColor.accent)
    }

    /// Highlights text that must not be translated, such as a place name.
    static func highlight(verbatim text: String) -> Text {
        Text(verbatim: text).foregroundStyle(AppColor.accent)
    }
}
