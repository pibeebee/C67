import C67Domain

struct RecommendationsBatch {
    let places: [RecommendedPlace]
    let warnings: [String]
    let synthetic: Bool

    init(result: PlanningResult) {
        places = result.candidates.map { RecommendedPlace(place: $0) }
        warnings = result.warnings
        synthetic = result.synthetic
    }

    init(places: [RecommendedPlace], warnings: [String] = [], synthetic: Bool = false) {
        self.places = places
        self.warnings = warnings
        self.synthetic = synthetic
    }
}
