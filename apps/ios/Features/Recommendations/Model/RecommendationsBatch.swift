import C67Domain

struct RecommendationsBatch: Sendable {
    let places: [RecommendedPlace]
    let warnings: [String]
    let synthetic: Bool
    let radiusKilometers: Int?

    init(result: PlanningResult) {
        places = result.candidates.map { RecommendedPlace(place: $0) }
        warnings = result.warnings
        synthetic = result.synthetic
        radiusKilometers = nil
    }

    init(places: [RecommendedPlace], warnings: [String] = [], synthetic: Bool = false, radiusKilometers: Int? = nil) {
        self.places = places
        self.warnings = warnings
        self.synthetic = synthetic
        self.radiusKilometers = radiusKilometers
    }
}
