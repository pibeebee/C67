import SwiftUI

/// Sketch HI-FI `PREFERENCES Q4`: when the trip happens.
struct TripTimingQuestionView: View {
    let selection: TripTiming?
    let select: (TripTiming) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text("\(QuestionTitle.highlight("When")) are we doing this?"),
            options: TripTiming.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
#Preview("Q4 · Unselected") {
    @Previewable @State var selection: TripTiming?
    PreferenceQuestionPreview {
        TripTimingQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("Q4 · Selected") {
    @Previewable @State var selection: TripTiming? = .inAFewDays
    PreferenceQuestionPreview {
        TripTimingQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("Q4 · Dark, large text") {
    @Previewable @State var selection: TripTiming? = .inAFewDays
    PreferenceQuestionPreview {
        TripTimingQuestionView(selection: selection, select: { selection = $0 }, skip: {})
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
#endif
