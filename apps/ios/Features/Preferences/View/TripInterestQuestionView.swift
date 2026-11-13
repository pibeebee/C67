import SwiftUI
import C67Domain

/// Sketch HI-FI `PREFERENCES Q1`: what sounds good today. Multi-select chips with Next.
struct TripInterestQuestionView: View {
    let selection: Set<TripInterest>
    let toggle: (TripInterest) -> Void
    let next: () -> Void
    let skip: () -> Void
    var refinements: [PlanningPreferenceLabel] = []
    var selectedRefinements: Set<String> = []
    var toggleRefinement: (String) -> Void = { _ in }
    @State private var showsRefinements = false

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
            if !refinements.isEmpty {
                Button("Refine interests (\(selectedRefinements.count))") { showsRefinements = true }
                    .accessibilityIdentifier("pocketRefineInterests")
            }
        } footer: {
            QuestionPrimaryButton("Next", action: next)
                .disabled(selection.isEmpty)
        }
        .sheet(isPresented: $showsRefinements) {
            PocketRefinementPicker(options: refinements, selected: selectedRefinements, toggle: toggleRefinement)
        }
    }
}

private struct PocketRefinementPicker: View {
    let options: [PlanningPreferenceLabel]
    let selected: Set<String>
    let toggle: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(Set(options.map(\.group))).sorted(), id: \.self) { group in
                    Section(group) {
                        ForEach(options.filter { $0.group == group && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) }) { option in
                            Button { toggle(option.id) } label: {
                                HStack {
                                    Text(option.title)
                                    Spacer()
                                    if selected.contains(option.id) { Image(systemName: "checkmark") }
                                }
                            }
                            .accessibilityIdentifier("pocketLabel-\(option.id)")
                            .accessibilityValue(selected.contains(option.id) ? "Selected" : "Not selected")
                        }
                    }
                }
            }
            .navigationTitle("Refine interests")
            .searchable(text: $query, prompt: "Search interests")
            .safeAreaInset(edge: .bottom) {
                QuestionPrimaryButton("Done") { dismiss() }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pocketRefinementsDone")
                    .padding()
                    .background(.regularMaterial)
            }
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
