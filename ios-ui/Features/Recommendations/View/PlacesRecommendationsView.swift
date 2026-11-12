import SwiftUI
import C67Domain

struct PlacesRecommendationsView: View {
    @State private var batch: RecommendationsBatch
    @State private var selected: [PlanningPlace]
    @State private var isRefreshing = false
    @State private var refreshFailed = false
    @State private var showsSelected = false
    let existing: [PlanningPlace]
    let refresh: @MainActor () async -> RecommendationsBatch?
    let continueWithoutSelection: (() -> Void)?
    let complete: @MainActor ([PlanningPlace]) -> Void
    let maximumAdditions: Int

    init(batch: RecommendationsBatch, existing: [PlanningPlace], selected: [PlanningPlace] = [],
         refresh: @escaping @MainActor () async -> RecommendationsBatch?,
         continueWithoutSelection: (() -> Void)? = nil,
         maximumAdditions: Int = 3,
         complete: @escaping @MainActor ([PlanningPlace]) -> Void) {
        _batch = State(initialValue: batch)
        _selected = State(initialValue: selected)
        self.existing = existing
        self.refresh = refresh
        self.continueWithoutSelection = continueWithoutSelection
        self.complete = complete
        self.maximumAdditions = maximumAdditions
    }

    private var existingIDs: Set<UUID> { Set(existing.map(\.id)) }
    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }
    private var selectionLimit: Int {
        let available = Set(batch.places.map(\.id)).subtracting(existingIDs).union(selectedIDs).count
        return min(maximumAdditions, max(0, 6 - existing.count), available)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Here’s what we \(Text("found").foregroundStyle(AppColor.accent)) for you")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Pull down to refresh recommendations")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                if batch.places.isEmpty {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Try refreshing or choose a place yourself.")
                    } actions: {
                        Button("Try again", action: retry)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(batch.places) { item in
                            RecommendationPlaceRow(item: item, isSelected: selectedIDs.contains(item.id),
                                                   isExisting: existingIDs.contains(item.id),
                                                   isDisabled: !selectedIDs.contains(item.id) && selected.count >= selectionLimit) {
                                toggle(item.place)
                            }
                        }
                    }
                }

                if refreshFailed {
                    Label("Recommendations couldn’t be refreshed. Your selection is still here.",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try again", action: retry)
                        .disabled(isRefreshing)
                }
                ForEach(batch.warnings, id: \.self) { warning in
                    Text(warning).font(.footnote).foregroundStyle(.secondary)
                }
                if batch.synthetic {
                    Text("Synthetic recommendations for demonstration.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refreshPlaces() }
        .background(AppColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(selected.count) of \(selectionLimit) places selected")
                        Spacer()
                        Button("My Places") { showsSelected = true }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected.count) of \(selectionLimit) places selected")
                        Button("My Places") { showsSelected = true }
                    }
                }
                .font(.body)
                Button(action: finish) {
                    Text("Next")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(AppColor.brand)
                .frame(maxWidth: .infinity)
                .disabled(selected.isEmpty || isRefreshing)
                .accessibilityIdentifier("recommendationsNext")
                if let continueWithoutSelection {
                    Button("Continue with my places", action: continueWithoutSelection)
                        .disabled(isRefreshing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
        }
        .sheet(isPresented: $showsSelected) {
            SelectedPlacesView(
                existing: existing,
                selected: $selected,
                details: Dictionary(batch.places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            )
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppColor.accent)
    }

    private func toggle(_ place: PlanningPlace) {
        if selectedIDs.contains(place.id) {
            selected.removeAll { $0.id == place.id }
        } else if selected.count < selectionLimit && !existingIDs.contains(place.id) {
            selected.append(place)
        }
    }

    private func retry() { Task { await refreshPlaces() } }

    private func refreshPlaces() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let updated = await refresh() {
            batch = updated
            refreshFailed = false
        } else {
            refreshFailed = true
        }
    }

    private func finish() { complete(selected) }
}

#if DEBUG
    #Preview("PLACES LISTS · Light") {
        RecommendationsDesignPreview(addedCount: 0)
    }

    #Preview("PLACES LIST ADDED · Light") {
        RecommendationsDesignPreview(addedCount: 3)
    }

    #Preview("PLACES LIST ADDED · Dark") {
        RecommendationsDesignPreview(addedCount: 3).preferredColorScheme(.dark)
    }
#endif
