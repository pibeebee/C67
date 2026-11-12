import SwiftUI

/// Sketch HI-FI `PREFERENCES Q1`: what sounds good today. Multi-select chips with Next.
struct TripInterestQuestionView: View {
    let selection: Set<TripInterest>
    let toggle: (TripInterest) -> Void
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        QuestionScaffold(
            title: Text("What sounds \(QuestionTitle.highlight("good")) today?"),
            contentSpacing: 40,
            skip: skip
        ) {
            FlowLayout(spacing: 8, lineSpacing: 14) {
                ForEach(TripInterest.allCases) { interest in
                    ChoiceChip(
                        title: interest.title,
                        systemImage: interest.systemImage,
                        isSelected: selection.contains(interest)
                    ) {
                        toggle(interest)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
        } footer: {
            QuestionPrimaryButton("Next", action: next)
                .disabled(selection.isEmpty)
        }
    }
}

#if DEBUG
    #Preview("Q1 · Unselected") {
        @Previewable @State var selection: Set<TripInterest> = []
        PreferenceQuestionPreview {
            TripInterestQuestionView(
                selection: selection,
                toggle: { selection.formSymmetricDifference([$0]) },
                next: {},
                skip: {}
            )
        }
    }

    #Preview("Q1 · Selected") {
        @Previewable @State var selection: Set<TripInterest> = [.foodie, .culture]
        PreferenceQuestionPreview {
            TripInterestQuestionView(
                selection: selection,
                toggle: { selection.formSymmetricDifference([$0]) },
                next: {},
                skip: {}
            )
        }
    }

    #Preview("Q1 · Dark, large text") {
        @Previewable @State var selection: Set<TripInterest> = [.nature]
        PreferenceQuestionPreview {
            TripInterestQuestionView(
                selection: selection,
                toggle: { selection.formSymmetricDifference([$0]) },
                next: {},
                skip: {}
            )
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
