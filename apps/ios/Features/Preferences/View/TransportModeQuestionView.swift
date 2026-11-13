import SwiftUI

/// Sketch HI-FI `PREFERENCES Q7`: how the traveller gets around.
struct TransportModeQuestionView: View {
    let selection: TransportMode?
    let select: (TransportMode) -> Void
    let skip: () -> Void

    var body: some View {
        SingleChoiceQuestionView(
            title: Text("How are we \(QuestionTitle.highlight("getting around"))?"),
            options: TransportMode.allCases,
            selection: selection,
            select: select,
            skip: skip
        )
    }
}

#if DEBUG
    #Preview("Q7 · Unselected") {
        @Previewable @State var selection: TransportMode?
        PreferenceQuestionPreview {
            TransportModeQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q7 · Selected") {
        @Previewable @State var selection: TransportMode? = .motorcycle
        PreferenceQuestionPreview {
            TransportModeQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
    }

    #Preview("Q7 · Dark, large text") {
        @Previewable @State var selection: TransportMode? = .motorcycle
        PreferenceQuestionPreview {
            TransportModeQuestionView(selection: selection, select: { selection = $0 }, skip: {})
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
