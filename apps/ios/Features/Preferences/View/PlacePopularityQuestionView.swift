import SwiftUI

/// Sketch HI-FI `PREFERENCES Q2`: popular spots or hidden gems.
struct PlacePopularityQuestionView: View {
    let selection: PlacePopularityPreference?
    let select: (PlacePopularityPreference) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text("\(QuestionTitle.highlight("Popular")) spots or \(QuestionTitle.highlight("hidden")) gems?"),
            options: PlacePopularityPreference.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
    #Preview("Q2 · Unselected") {
        @Previewable @State var selection: PlacePopularityPreference?
        PreferenceQuestionPreview {
            PlacePopularityQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q2 · Selected") {
        @Previewable @State var selection: PlacePopularityPreference? = .both
        PreferenceQuestionPreview {
            PlacePopularityQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q2 · Dark, large text") {
        @Previewable @State var selection: PlacePopularityPreference? = .both
        PreferenceQuestionPreview {
            PlacePopularityQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
