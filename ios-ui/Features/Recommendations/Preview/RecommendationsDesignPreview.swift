#if DEBUG
    import SwiftUI

    struct RecommendationsDesignPreview: View {
        let addedCount: Int
        @State private var showsNotice = false

        var body: some View {
            NavigationStack {
                PlacesRecommendationsView(batch: RecommendationsPreviewData.batch, existing: [],
                                          selected: Array(RecommendationsPreviewData.batch.places.prefix(addedCount).map(\.place)),
                                          refresh: { RecommendationsPreviewData.batch },
                                          complete: { _ in showsNotice = true })
                    .toolbar(.hidden, for: .navigationBar)
                    .alert("Design preview", isPresented: $showsNotice) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("These are sample places from Sketch. Plan a trip in the app to use real recommendations.")
                    }
            }
        }
    }

    #Preview("PLACES LISTS · 0 of 3") {
        RecommendationsDesignPreview(addedCount: 0)
    }

    #Preview("PLACES LIST ADDED · 3 of 3") {
        RecommendationsDesignPreview(addedCount: 3)
    }

    #Preview("PLACES LIST ADDED · Dark") {
        RecommendationsDesignPreview(addedCount: 3).preferredColorScheme(.dark)
    }
#endif
