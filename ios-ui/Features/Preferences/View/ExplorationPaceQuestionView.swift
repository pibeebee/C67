import SwiftUI

/// Sketch HI-FI `PREFERENCES Q3`: how much exploring (number of stops).
struct ExplorationPaceQuestionView: View {
    let selection: ExplorationPace?
    let select: (ExplorationPace) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text("How \(QuestionTitle.highlight("much")) exploring are we up for?"),
            options: ExplorationPace.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
    #Preview("Q3 · Unselected") {
        @Previewable @State var selection: ExplorationPace?
        PreferenceQuestionPreview {
            ExplorationPaceQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q3 · Selected") {
        @Previewable @State var selection: ExplorationPace? = .packed
        PreferenceQuestionPreview {
            ExplorationPaceQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q3 · Dark, large text") {
        @Previewable @State var selection: ExplorationPace? = .packed
        PreferenceQuestionPreview {
            ExplorationPaceQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
