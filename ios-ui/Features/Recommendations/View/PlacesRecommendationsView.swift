import SwiftUI
import C67Domain

struct PlacesRecommendationsView: View {
    let batch: RecommendationsBatch
    let selected: [RecommendedPlace]
    var isLoading = false
    var error: String?
    /// The older planning editor still follows its existing six-place contract.
    /// The recommendations-first creation flow leaves this nil.
    var maximumSelection: Int?
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
    let cancel: () -> Void
    let toggle: (RecommendedPlace) -> Void
    let findPlace: () -> Void
    let complete: () -> Void
    @State private var showsSelected = false
    @State private var retryTask: Task<Void, Never>?

    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }
    private var selectedPlaces: Binding<[PlanningPlace]> {
        Binding(get: { selected.map(\.place) }, set: { remaining in
            let ids = Set(remaining.map(\.id))
            for item in selected where !ids.contains(item.id) { toggle(item) }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Fantastic! Here’s what we \(Text("found").foregroundStyle(AppColor.accent)) for you")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Pull down to refresh recommendations")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                if isLoading { ProgressView("Finding places…").frame(maxWidth: .infinity).padding() }
                if batch.places.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Try refreshing, adjust your preferences, or search for a place.")
                    } actions: {
                        Button("Try again", action: retry)
                        Button("Search for a place", action: findPlace)
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(batch.places) { item in
                        RecommendationPlaceRow(item: item, isSelected: selectedIDs.contains(item.id),
                                               isExisting: false,
                                               isDisabled: !selectedIDs.contains(item.id) && maximumSelection.map { selected.count >= $0 } == true) { toggle(item) }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Try again", action: retry).disabled(isLoading)
                }
                ForEach(batch.warnings, id: \.self) { warning in
                    Text(warning).font(.footnote).foregroundStyle(.secondary)
                }
                if batch.synthetic {
                    Text("Synthetic recommendations for demonstration.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !batch.places.isEmpty {
                    Text("Check opening hours and any facilities you need before visiting.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TripRecommendationsMap(places: batch.places)
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task { await load() }
        .refreshable { await refresh() }
        .onDisappear { retryTask?.cancel(); cancel() }
        .background(AppColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(selected.count) places selected")
                        Spacer()
                        Button("My Places") { showsSelected = true }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected.count) places selected")
                        Button("My Places") { showsSelected = true }
                    }
                }
                Button("Search for a place", action: findPlace)
                if let maximumSelection {
                    Text("Choose up to \(maximumSelection) additional places.").font(.footnote).foregroundStyle(.secondary)
                }
                QuestionPrimaryButton("Next", action: complete)
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("recommendationsNext")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
        }
        .sheet(isPresented: $showsSelected) {
            SelectedPlacesView(existing: [], selected: selectedPlaces,
                               details: Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppColor.accent)
    }

    private func retry() {
        guard !isLoading else { return }
        retryTask?.cancel()
        retryTask = Task { await refresh() }
    }
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
