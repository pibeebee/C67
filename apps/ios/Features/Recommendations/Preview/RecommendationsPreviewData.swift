#if DEBUG
    import Foundation
    import C67Domain

    /// These example venues and attributes come from Sketch and are never sent to a repository.
    enum RecommendationsPreviewData {
        static let ids = [UUID(), UUID(), UUID(), UUID(), UUID()]
        static let names = ["ALDI’S BURGER", "FamiCafé by FamilyMart", "ROH Project", "Pizza 4P's Indonesia", "Graha Bakti Budaya"]
        static let categories = ["Culinary", "Culinary", "Museum Art", "Culinary", "Performing Art"]
        static let addresses = ["Jl. Cemp. Putih Tim. 12 No.8A", "Jl Muara Beliti, Central Jakarta", "Jalan Surabaya, Central Jakarta", "Jalan Benhil, Central Jakarta", "Jalan Cikini, Central Jakarta"]
        static let images = ["itinerary-aldis", "itinerary-famicafe", "itinerary-roh", "places-pizza", "places-graha"]

        static let batch = RecommendationsBatch(places: ids.indices.map { index in
            RecommendedPlace(place: PlanningPlace(id: ids[index], name: names[index],
                                                  location: .init(latitude: -6.19, longitude: 106.84), visitSeconds: 1800),
                             category: categories[index], address: addresses[index], previewImage: images[index])
        }, synthetic: true)
    }
#endif
