import SwiftUI

/// Sketch HI-FI `PREFERENCES Q5`: preferred time of day.
struct DayPartQuestionView: View {
    let selection: DayPart?
    let select: (DayPart) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text("When do you \(QuestionTitle.highlight("prefer")) to explore?"),
            options: DayPart.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
#Preview("Q5 · Unselected") {
    @Previewable @State var selection: DayPart?
    PreferenceQuestionPreview {
        DayPartQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("Q5 · Selected") {
    @Previewable @State var selection: DayPart? = .evening
    PreferenceQuestionPreview {
        DayPartQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("Q5 · Dark, large text") {
    @Previewable @State var selection: DayPart? = .evening
    PreferenceQuestionPreview {
        DayPartQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
#endif
