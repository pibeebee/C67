import Foundation
import C67Domain

/// Optional display metadata is supplied only when it is actually available.
struct RecommendedPlace: Identifiable, Equatable {
    var place: PlanningPlace
    var category: String?
    var address: String?
    var previewImage: String?

    var id: UUID { place.id }
}
