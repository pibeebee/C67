#if DEBUG
    import SwiftUI

    struct HomeAddedTripDesignPreview: View {
        var body: some View {
            TabView {
                Tab("Trip", systemImage: "location") {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Today").font(.headline)
                                NavigationLink {
                                    SavedTripDesignPreview()
                                } label: {
                                    TripHomeRow(trip: TripDesignPreviewData.trip(), previewImages: ["itinerary-aldis", "itinerary-famicafe", "itinerary-roh"])
                                }.buttonStyle(.plain)
                            }.padding(20)
                        }
                        .safeAreaInset(edge: .top, spacing: 0) {
                            TripHomeHeader(locationTitle: "Kemayoran, Central Jakarta", chooseLocation: {}, addTrip: {}, addSpecificPlace: {})
                        }
                        .background(AppColor.canvas)
                    }
                }
                Tab("History", systemImage: "clock.arrow.circlepath") {
                    ContentUnavailableView("Design preview", systemImage: "clock")
                }
            }
        }
    }
    #Preview("HOME ADDED TRIP") { HomeAddedTripDesignPreview() }
    #Preview("HOME Copy 3 · Populated Home") { HomeAddedTripDesignPreview() }
    #Preview("HOME ADDED TRIP · Dark") { HomeAddedTripDesignPreview().preferredColorScheme(.dark) }
#endif
