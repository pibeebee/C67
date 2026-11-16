import SwiftUI
import C67Domain

/// Multi-select themes and preferences for the first trip question.
struct TripInterestQuestionView: View {
    let selection: Set<TripInterest>
    let toggle: (TripInterest) -> Void
    let next: () -> Void
    let skip: () -> Void
    var supportedRefinements: [PlanningPreferenceLabel] = []
    var selectedRefinements: Set<String> = []
    var toggleRefinement: (String) -> Void = { _ in }
    @State private var query = ""
    @Namespace private var preferenceAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let quickPicks = ["matcha", "street_food_area", "sunset_viewing", "art_gallery", "city_park", "thrift_shop", "cinema", "bowling_alley", "mangrove_park", "photography_activity", "museum", "spa", "karaoke", "go_kart"]

    private var options: [(option: TripPreferenceCatalog.Option, symbol: String)] {
        TripPreferenceCatalog.groups.flatMap { group in
            group.options.map { (option: $0, symbol: group.systemImage) }
        }
    }

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = options.filter { selectedRefinements.contains($0.option.id) }
        let visible = term.isEmpty ? options.filter { quickPicks.contains($0.option.id) && !selectedRefinements.contains($0.option.id) }.sorted {
            (quickPicks.firstIndex(of: $0.option.id) ?? 0) < (quickPicks.firstIndex(of: $1.option.id) ?? 0)
        } : options.filter { String(localized: $0.option.title).localizedStandardContains(term) }
        QuestionScaffold(title: Text("What sounds \(QuestionTitle.highlight("good")) today?"), contentSpacing: 24, skip: skip) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search place types or activities", text: $query)
                            .accessibilityIdentifier("preferenceSearch")
                        if !query.isEmpty {
                            Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly)
                        }
                    }
                    .padding(12).background(AppColor.surface, in: .capsule)
                    Text("Search more places, activities, and interests")
                        .font(.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 12)
                }
                if term.isEmpty && !selected.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(selected, id: \.option.id) { item in
                            ChoiceChip(title: item.option.title, systemImage: item.symbol, isSelected: true) { animateToggle(item.option.id) }
                                .matchedGeometryEffect(id: item.option.id, in: preferenceAnimation)
                                .accessibilityIdentifier("selectedPreference-\(item.option.id)")
                        }
                    }
                }
                Text(term.isEmpty ? "Quick picks" : "Search results").font(.headline)
                if visible.isEmpty && !term.isEmpty {
                    ContentUnavailableView.search(text: term)
                } else {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(visible, id: \.option.id) { item in
                            ChoiceChip(title: item.option.title, systemImage: item.symbol,
                                       isSelected: selectedRefinements.contains(item.option.id)) { animateToggle(item.option.id) }
                                .matchedGeometryEffect(id: item.option.id, in: preferenceAnimation)
                                .accessibilityIdentifier("pocketLabel-\(item.option.id)")
                        }
                    }
                }
                if term.isEmpty {
                    Text("Explore by category").font(.headline)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(TripInterest.allCases) { interest in
                            ChoiceChip(title: interest.title, systemImage: interest.systemImage,
                                       isSelected: selection.contains(interest)) { toggle(interest) }
                        }
                    }
                }
                let extra = supportedRefinements.filter { !TripPreferenceCatalog.ids.contains($0.id) && (term.isEmpty ? selectedRefinements.contains($0.id) : $0.title.localizedStandardContains(term)) }
                ForEach(extra) { option in
                    Button { toggleRefinement(option.id) } label: {
                        Label(option.title, systemImage: "tag")
                    }
                    .accessibilityIdentifier("pocketLabel-\(option.id)")
                }
            }
        } footer: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    Text("\(selection.count + selectedRefinements.count) selected")
                        .font(.subheadline).fixedSize()
                    QuestionPrimaryButton("Next", action: next)
                        .disabled(selection.isEmpty && selectedRefinements.isEmpty)
                        .frame(minWidth: 100)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(selection.count + selectedRefinements.count) selected").font(.subheadline)
                    QuestionPrimaryButton("Next", action: next)
                        .disabled(selection.isEmpty && selectedRefinements.isEmpty)
                }
            }
        }
    }

    private func animateToggle(_ id: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            toggleRefinement(id)
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
