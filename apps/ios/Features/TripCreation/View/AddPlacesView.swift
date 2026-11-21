import SwiftUI
import C67Domain

/// The six ADD PLACES states share one search and selection surface.
struct AddPlacesView: View {
    @Binding var query: String
    let results: [RecommendedPlace]
    let selected: [RecommendedPlace]
    var isSearching = false
    var hasSearched = false
    var showsPreviousResults = false
    var error: String?
    var synthetic = false
    var initiallyFocused = false
    var maximumSelection: Int?
    var origin: PlanningPoint?
    let search: () async -> Void
    let toggle: (RecommendedPlace) -> Void
    let next: () -> Void
    @State private var showsSelected = false
    @State private var rejectedSelectionCount = 0
    @FocusState private var searchFocused: Bool

    private var displayed: [RecommendedPlace] { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (results.isEmpty ? selected : results) : results }
    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if !displayed.isEmpty, !query.isEmpty {
                    Text(showsPreviousResults ? "Previous search results" : "Search results")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if isSearching { ProgressView("Searching places…").padding() }
                if let error {
                    RecoveryNotice(title: "Search unavailable", message: error, icon: "wifi.exclamationmark",
                                   primary: .init(title: "Try again") { Task { await search() } })
                } else if displayed.isEmpty && !isSearching && (hasSearched || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    ContentUnavailableView(query.isEmpty ? "Find your places" : "No places found",
                                           systemImage: "magnifyingglass",
                                           description: Text(query.isEmpty ? "Search for a place to add it to your trip." : "Try a different name or location."))
                }
                ForEach(displayed) { item in
                    let isLocked = maximumSelection.map { !selectedIDs.contains(item.id) && selected.count >= $0 } ?? false
                    AddPlaceRow(item: item, isSelected: selectedIDs.contains(item.id), isDisabled: false, origin: origin) {
                        isLocked ? rejectedSelectionCount += 1 : toggle(item)
                    }
                    .opacity(isLocked ? 0.45 : 1)
                    .accessibilityHint(isLocked ? Text("Remove a place to add this one.") : Text(""))
                }
                if synthetic {
                    Text("Synthetic place search · demonstration only")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search place", text: $query, axis: .vertical)
                    .lineLimit(1 ... 2)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .onChange(of: query) { _, value in
                        if value.contains("\n") {
                            query = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            searchFocused = false
                        }
                    }
                    .accessibilityIdentifier("addPlacesSearch")
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(minHeight: 48)
            .background(.regularMaterial, in: .capsule)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(AppColor.canvas)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(selected.count) places selected")
                    .accessibilityIdentifier("placesSelectedCount")
                PlaceSelectionStatus(count: selected.count, minimum: 3, maximum: maximumSelection,
                                     rejectedCount: rejectedSelectionCount)
                if let limit = maximumSelection, selected.count > limit {
                    Button("Review My Places") { showsSelected = true }
                }
                QuestionPrimaryButton("Next") { searchFocused = false; next() }
                    .disabled(selected.count < 3)
                    .accessibilityIdentifier("addPlacesNext")
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
        }
        .navigationTitle("Add Specific Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("My Places", systemImage: "list.bullet.rectangle") { showsSelected = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brand)
                    .accessibilityIdentifier("addPlacesSelection")
            }
        }
        .sheet(isPresented: $showsSelected) {
            PlacesSelectionSheet(places: selected, remove: toggle)
        }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                await search()
            } catch { }
        }
        .task { if initiallyFocused { searchFocused = true } }
    }
}
