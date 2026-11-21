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
    @State private var rejectedSelectionCount = 0
    @Namespace private var preferenceAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maximumSelectionCount = PreferenceAnswers.maximumInterestSelections

    private let quickPicks = ["matcha", "street_food_area", "sunset_viewing", "art_gallery", "city_park", "thrift_shop", "cinema", "bowling_alley", "mangrove_park", "photography_activity", "museum", "spa", "karaoke", "go_kart"]

    private var options: [(option: TripPreferenceCatalog.Option, symbol: String)] {
        TripPreferenceCatalog.groups.flatMap { group in
            group.options.map { (option: $0, symbol: group.systemImage) }
        }
    }

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = options.filter { selectedRefinements.contains($0.option.id) }
        let selectionCount = selection.count + selectedRefinements.count
        let isAtSelectionLimit = selectionCount >= maximumSelectionCount
        let visible = term.isEmpty ? options.filter { quickPicks.contains($0.option.id) && !selectedRefinements.contains($0.option.id) }.sorted {
            (quickPicks.firstIndex(of: $0.option.id) ?? 0) < (quickPicks.firstIndex(of: $1.option.id) ?? 0)
        } : options.filter { String(localized: $0.option.title).localizedStandardContains(term) }
        QuestionScaffold(title: Text("What sounds \(QuestionTitle.highlight("good")) today?"), contentSpacing: 24, skip: skip) {
            VStack(alignment: .leading, spacing: 20) {
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
                if term.isEmpty && (!selected.isEmpty || !selection.isEmpty) {
                    HStack {
                        Text("Your interests")
                            .font(.headline)
                        Spacer()
                        selectionMeter(count: selectionCount, isFull: isAtSelectionLimit)
                    }
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(TripInterest.allCases.filter { selection.contains($0) }) { interest in
                            ChoiceChip(title: interest.title, systemImage: interest.systemImage, isSelected: true) {
                                animateInterestToggle(interest)
                            }
                            .matchedGeometryEffect(id: "interest-\(interest.id)", in: preferenceAnimation)
                        }
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
                            let isLocked = isAtSelectionLimit && !selectedRefinements.contains(item.option.id)
                            ChoiceChip(title: item.option.title, systemImage: item.symbol,
                                       isSelected: selectedRefinements.contains(item.option.id)) {
                                isLocked ? rejectSelection() : animateToggle(item.option.id)
                            }
                            .lockedAtSelectionLimit(isLocked)
                            .matchedGeometryEffect(id: item.option.id, in: preferenceAnimation)
                            .accessibilityIdentifier("pocketLabel-\(item.option.id)")
                        }
                    }
                }
                if term.isEmpty {
                    Text("Explore by category").font(.headline)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(TripInterest.allCases.filter { !selection.contains($0) }) { interest in
                            ChoiceChip(title: interest.title, systemImage: interest.systemImage,
                                       isSelected: false) {
                                isAtSelectionLimit ? rejectSelection() : animateInterestToggle(interest)
                            }
                            .lockedAtSelectionLimit(isAtSelectionLimit)
                            .matchedGeometryEffect(id: "interest-\(interest.id)", in: preferenceAnimation)
                        }
                    }
                }
                let extra = supportedRefinements.filter { !TripPreferenceCatalog.ids.contains($0.id) && (term.isEmpty ? selectedRefinements.contains($0.id) : $0.title.localizedStandardContains(term)) }
                ForEach(extra) { option in
                    let isLocked = isAtSelectionLimit && !selectedRefinements.contains(option.id)
                    Button { isLocked ? rejectSelection() : toggleRefinement(option.id) } label: {
                        Label(option.title, systemImage: "tag")
                    }
                    .lockedAtSelectionLimit(isLocked)
                    .accessibilityIdentifier("pocketLabel-\(option.id)")
                }
            }
        } footer: {
            QuestionPrimaryButton("Next", action: next)
                .disabled(selection.isEmpty && selectedRefinements.isEmpty)
        }
        .sensoryFeedback(.warning, trigger: rejectedSelectionCount)
    }

    /// Five dots that fill as interests are chosen; "Full" appears once the cap is reached.
    private func selectionMeter(count: Int, isFull: Bool) -> some View {
        HStack(spacing: 6) {
            if isFull {
                Text("Full")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .transition(.opacity)
            }
            HStack(spacing: 5) {
                ForEach(0 ..< maximumSelectionCount, id: \.self) { index in
                    Circle()
                        .fill(index < count ? AppColor.brand : AppColor.tertiaryFill)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: rejectedSelectionCount) { meter, offset in
            meter.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(-5), duration: 0.07)
                SpringKeyframe(CGFloat(5), duration: 0.07)
                SpringKeyframe(CGFloat(-3), duration: 0.07)
                SpringKeyframe(CGFloat.zero, duration: 0.12)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(maximumSelectionCount) interests chosen")
        .accessibilityIdentifier("interestSelectionCount")
    }

    /// Tapping an option while the cap is reached explains the limit instead of doing nothing.
    private func rejectSelection() {
        rejectedSelectionCount += 1
    }

    private func animateToggle(_ id: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            toggleRefinement(id)
        }
    }

    private func animateInterestToggle(_ interest: TripInterest) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            toggle(interest)
        }
    }
}

private extension View {
    /// Dims an option that can't be added while the interest cap is reached. It stays tappable
    /// so the tap can answer with feedback, and VoiceOver hears why it isn't available.
    func lockedAtSelectionLimit(_ isLocked: Bool) -> some View {
        opacity(isLocked ? 0.45 : 1)
            .accessibilityHint(isLocked ? Text("Remove an interest to choose this one.") : Text(""))
    }
}

#if DEBUG
    #Preview("Q1 · Full") {
        @Previewable @State var answers = PreferenceAnswers(
            interests: [.foodie, .culture, .nature],
            refinements: ["matcha", "photography_activity"]
        )
        PreferenceQuestionPreview {
            TripInterestQuestionView(
                selection: answers.interests,
                toggle: { answers.toggle($0) },
                next: {},
                skip: {},
                selectedRefinements: answers.refinements,
                toggleRefinement: { answers.toggleRefinement($0) }
            )
        }
    }

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
