import SwiftUI

/// The six ADD PLACES states share one search and selection surface.
struct AddPlacesView: View {
    @Binding var query: String
    let results: [RecommendedPlace]
    let selected: [RecommendedPlace]
    var isSearching = false
    var error: String?
    var synthetic = false
    var initiallyFocused = false
    let search: () async -> Void
    let toggle: (RecommendedPlace) -> Void
    let next: () -> Void
    @State private var showsSelected = false
    @FocusState private var searchFocused: Bool

    private var displayed: [RecommendedPlace] { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (results.isEmpty ? selected : results) : results }
    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if isSearching { ProgressView("Searching places…").padding() }
                if let error {
                    ContentUnavailableView {
                        Label("Search unavailable", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") { Task { await search() } }
                    }
                } else if displayed.isEmpty && !isSearching {
                    ContentUnavailableView(query.isEmpty ? "Find your places" : "No places found",
                                           systemImage: "magnifyingglass",
                                           description: Text(query.isEmpty ? "Search for a place or address to add it to your trip." : "Try a different name or area."))
                }
                ForEach(displayed) { item in
                    AddPlaceRow(item: item, isSelected: selectedIDs.contains(item.id), isDisabled: false) { toggle(item) }
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
                QuestionPrimaryButton("Next") { searchFocused = false; next() }
                    .disabled(selected.isEmpty)
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
