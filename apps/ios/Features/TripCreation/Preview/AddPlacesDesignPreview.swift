#if DEBUG
    import SwiftUI

    struct AddPlacesDesignPreview: View {
        var initialQuery = ""
        var addedCount = 0
        var focused = false
        var showsSheet = false
        @State private var query: String
        @State private var selected: [RecommendedPlace]
        @State private var notice = false
        @State private var sheet: Bool

        init(initialQuery: String = "", addedCount: Int = 0, focused: Bool = false, showsSheet: Bool = false) {
            self.initialQuery = initialQuery
            self.addedCount = addedCount
            self.focused = focused
            self.showsSheet = showsSheet
            _query = State(initialValue: initialQuery)
            let places = RecommendationsPreviewData.batch.places
            _selected = State(initialValue: addedCount == 4 ? [places[3]] + Array(places.prefix(3)) : Array(places.prefix(addedCount)))
            _sheet = State(initialValue: showsSheet)
        }

        var body: some View {
            NavigationStack {
                AddPlacesView(query: $query,
                              results: query.isEmpty ? Array(RecommendationsPreviewData.batch.places.prefix(3)) : [RecommendationsPreviewData.batch.places[3]],
                              selected: selected, synthetic: true, initiallyFocused: focused,
                              search: {}, toggle: toggle, next: { notice = true })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back", systemImage: "chevron.backward") { notice = true }.labelStyle(.iconOnly)
                        }
                    }
            }
            .sheet(isPresented: $sheet) { PlacesSelectionSheet(places: selected, remove: toggle) }
            .alert("Design preview", isPresented: $notice) { Button("OK", role: .cancel) {} } message: {
                Text("Sample content from Sketch. Create a trip in the app to plan and save real selections.")
            }
        }

        private func toggle(_ item: RecommendedPlace) {
            if let index = selected.firstIndex(where: { $0.id == item.id }) { selected.remove(at: index) }
            else if selected.count < 6 { selected.append(item) }
        }
    }

    #Preview("ADD PLACES") { AddPlacesDesignPreview() }
    #Preview("ADD PLACES SEARCH") { AddPlacesDesignPreview(focused: true) }
    #Preview("ADD PLACES SEARCH PIZZA") { AddPlacesDesignPreview(initialQuery: "Pizza", focused: true) }
    #Preview("ADD PLACES SEARCH PIZZA ADDED") { AddPlacesDesignPreview(initialQuery: "Pizza", addedCount: 4, focused: true) }
    #Preview("ADD PLACES Copy · Four selected") { AddPlacesDesignPreview(addedCount: 4) }
    #Preview("ADD PLACES Copy 2 · Places sheet") { AddPlacesDesignPreview(addedCount: 4, showsSheet: true) }
    #Preview("ADD PLACES · Dark, large text") {
        AddPlacesDesignPreview(addedCount: 4).preferredColorScheme(.dark).dynamicTypeSize(.accessibility3)
    }
#endif
