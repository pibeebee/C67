import SwiftUI

/// Sketch HI-FI `PLACES MAIN COURSE STAY` and `… STAY SELECTED`: how long to stay at the main spot.
struct StayDurationQuestionView: View {
    let placeName: String
    let selection: StayDuration?
    let select: (StayDuration) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text(
                "How \(QuestionTitle.highlight("long")) are we hanging out at \(QuestionTitle.highlight(verbatim: placeName))?"
            ),
            options: StayDuration.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
#Preview("PLACES MAIN COURSE STAY") {
    @Previewable @State var selection: StayDuration?
    PreferenceQuestionPreview {
        StayDurationQuestionView(placeName: "ROH Project", selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("PLACES MAIN COURSE STAY SELECTED") {
    @Previewable @State var selection: StayDuration? = .ninetyMinutes
    PreferenceQuestionPreview {
        StayDurationQuestionView(placeName: "ROH Project", selection: selection, select: { selection = $0 }, skip: {})
    }
}

#Preview("STAY · Dark, large text") {
    @Previewable @State var selection: StayDuration? = .ninetyMinutes
    PreferenceQuestionPreview {
        StayDurationQuestionView(placeName: "FamiCafé by FamilyMart", selection: selection, select: { selection = $0 }, skip: {})
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
#endif
