#if DEBUG
    import Foundation
    import C67Domain

    /// Sketch reference content, isolated from repositories and the production planning path.
    enum ItineraryPreviewData {
        static let ids = [UUID(), UUID(), UUID()]
        static let startsAt = Date(timeIntervalSince1970: 1_794_358_800)
        static let names = ["ALDI’S BURGER", "FamiCafé by FamilyMart", "ROH Project"]
        static let points = [PlanningPoint(latitude: -6.1905, longitude: 106.8397),
                             PlanningPoint(latitude: -6.1920, longitude: 106.8410),
                             PlanningPoint(latitude: -6.1946, longitude: 106.8401)]
        static let arrivals: [TimeInterval] = [0, 2160, 4680]
        static let departures: [TimeInterval] = [1800, 3600, 6600]
        static let travels = [0, 360, 1080]

        static let input = PlanningInput(title: "Sketch sample itinerary", origin: points[0],
                                         places: ids.indices.map {
                                             PlanningPlace(id: ids[$0], name: names[$0], location: points[$0],
                                                           visitSeconds: Int(departures[$0] - arrivals[$0]))
                                         }, preferences: "Sketch design reference", startsAt: startsAt,
                                         finishBy: startsAt.addingTimeInterval(6600), timeZone: "Asia/Jakarta", mode: .walking)

        static let proposal = PlanProposal(id: UUID(), input: input,
                                           stops: ids.indices.map {
                                               ScheduledPlanningStop(id: ids[$0], name: names[$0], location: points[$0],
                                                                     arrivalAt: startsAt.addingTimeInterval(arrivals[$0]),
                                                                     departureAt: startsAt.addingTimeInterval(departures[$0]),
                                                                     visitSeconds: Int(departures[$0] - arrivals[$0]),
                                                                     travelSeconds: travels[$0], warnings: [])
                                           }, finishesAt: startsAt.addingTimeInterval(6600), feasible: true,
                                           explanation: "Sample content from the supplied Sketch design. Times, weather, distances and map points are illustrative; no live route or weather request was made.",
                                           warnings: [], evidence: [], synthetic: true)

        static let details: [UUID: ItineraryStopDetails] = [
            ids[0]: .init(category: "Culinary", photoAsset: "itinerary-aldis", weatherAdvice: "32° · Bring water for the walk", weatherSymbol: "sun.max"),
            ids[1]: .init(category: "Culinary", photoAsset: "itinerary-famicafe", weatherAdvice: "32° · Bring water for the walk", weatherSymbol: "sun.max", distance: "450 m"),
            ids[2]: .init(category: "Museum Art", photoAsset: "itinerary-roh", weatherAdvice: "30° · Rain possible · Pack umbrella", weatherSymbol: "cloud.rain", distance: "1.3 km")
        ]
    }
#endif
