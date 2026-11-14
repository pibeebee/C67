#if DEBUG
    import SwiftUI

    struct RecommendationsDesignPreview: View {
        let addedCount: Int
        @State private var showsNotice = false
        @State private var selected: [RecommendedPlace]

        init(addedCount: Int) {
            self.addedCount = addedCount
            _selected = State(initialValue: Array(RecommendationsPreviewData.batch.places.prefix(addedCount)))
        }

        var body: some View {
            NavigationStack {
                PlacesRecommendationsView(batch: RecommendationsPreviewData.batch, selected: selected,
                                          load: {}, refresh: {}, cancel: {}, toggle: { item in
                                              if selected.contains(where: { $0.id == item.id }) {
                                                  selected.removeAll { $0.id == item.id }
                                              } else { selected.append(item) }
                                          }, findPlace: { showsNotice = true }, complete: { showsNotice = true })
                    .toolbar(.hidden, for: .navigationBar)
                    .alert("Design preview", isPresented: $showsNotice) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("These are sample places from Sketch. Plan a trip in the app to use real recommendations.")
                    }
            }
        }
    }

    #Preview("PLACES LISTS · No selection") {
        RecommendationsDesignPreview(addedCount: 0)
    }

    #Preview("PLACES LIST ADDED · Three selected") {
        RecommendationsDesignPreview(addedCount: 3)
    }

    #Preview("PLACES LIST ADDED · Dark") {
        RecommendationsDesignPreview(addedCount: 3).preferredColorScheme(.dark)
    }
#endif
