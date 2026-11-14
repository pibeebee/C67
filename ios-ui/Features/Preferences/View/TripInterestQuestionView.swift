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
            TripPreferenceGroups(
                selected: selectedRefinements,
                hasUnmatchedSelection: !selectedRefinements.isSubset(of: Set(supportedRefinements.map(\.id))),
                search: { showsRefinements = true },
                toggle: toggleRefinement
            )
        } footer: {
            QuestionPrimaryButton("Next", action: next)
                .disabled(selection.isEmpty && selectedRefinements.isEmpty)
        }
        .sheet(isPresented: $showsRefinements) {
            TripPreferenceSearch(
                selected: selectedRefinements,
                additionalOptions: supportedRefinements.filter { !TripPreferenceCatalog.ids.contains($0.id) },
                toggle: toggleRefinement
            )
        }
    }
}

private struct TripPreferenceGroups: View {
    let selected: Set<String>
    let hasUnmatchedSelection: Bool
    let search: () -> Void
    let toggle: (String) -> Void
    @State private var expandedGroup: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Preferences")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !selected.isEmpty {
                    Text("\(selected.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Search preferences", systemImage: "magnifyingglass", action: search)
                .accessibilityIdentifier("pocketRefineInterests")

            ForEach(TripPreferenceCatalog.groups) { group in
                let selectedCount = group.options.count { selected.contains($0.id) }
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedGroup == group.id },
                    set: { isExpanded in
                        if isExpanded { expandedGroup = group.id }
                        else if expandedGroup == group.id { expandedGroup = nil }
                    }
                )) {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(group.options) { option in
                            ChoiceChip(title: option.title, isSelected: selected.contains(option.id)) {
                                toggle(option.id)
                            }
                            .accessibilityIdentifier("pocketLabel-\(option.id)")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Label {
                            Text(group.title)
                        } icon: {
                            Image(systemName: group.systemImage)
                        }
                        Spacer(minLength: 8)
                        if selectedCount > 0 {
                            Text("\(selectedCount) selected")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(AppColor.primaryText)
                }
            }
            if hasUnmatchedSelection {
                Text("Some selected preferences aren’t used in recommendations yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct TripPreferenceSearch: View {
    let selected: Set<String>
    let additionalOptions: [PlanningPreferenceLabel]
    let toggle: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = TripPreferenceCatalog.groups.compactMap { group -> TripPreferenceCatalog.Group? in
            let options = group.options.filter {
                term.isEmpty || String(localized: $0.title).localizedStandardContains(term)
            }
            guard !options.isEmpty else { return nil }
            return .init(id: group.id, title: group.title, systemImage: group.systemImage, options: options)
        }
        let additional = additionalOptions.filter {
            term.isEmpty || $0.title.localizedStandardContains(term) ||
                $0.id.replacingOccurrences(of: "_", with: " ").localizedStandardContains(term)
        }
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.options) { option in
                            TripPreferenceSearchRow(id: option.id, title: Text(option.title),
                                                    isSelected: selected.contains(option.id), toggle: toggle)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
                if !additional.isEmpty {
                    Section("More preferences") {
                        ForEach(additional) { option in
                            TripPreferenceSearchRow(id: option.id, title: Text(option.title),
                                                    isSelected: selected.contains(option.id), toggle: toggle)
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty && additional.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            }
            .navigationTitle("Preferences")
            .searchable(text: $query, prompt: "Search preferences")
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

private struct TripPreferenceSearchRow: View {
    let id: String
    let title: Text
    let isSelected: Bool
    let toggle: (String) -> Void

    var body: some View {
        Button { toggle(id) } label: {
            HStack {
                title
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("pocketLabel-\(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
