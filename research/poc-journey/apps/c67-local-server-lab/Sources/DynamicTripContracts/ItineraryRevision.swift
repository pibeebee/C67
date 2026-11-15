import Foundation
import PlaceContextEngine

public enum RevisionPlaceOrigin: String, Codable, Sendable { case recommendation, userSelected, previousPlan }
public struct RevisionPlaceSource: Codable, Sendable {
    public var placeID: String
    public var origin: RevisionPlaceOrigin
    public var recommendationID: UUID?
    public var profileRevision: Int?
    public init(placeID: String, origin: RevisionPlaceOrigin, recommendationID: UUID? = nil, profileRevision: Int? = nil) {
        self.placeID = placeID; self.origin = origin; self.recommendationID = recommendationID; self.profileRevision = profileRevision
    }
}
public struct ItineraryRevisionInput: Codable, Sendable {
    public var draftID: UUID
    public var parentRevisionID: UUID
    public var plan: DynamicPlanInput
    public var requiredPlaceIDs: [String]
    public var sources: [RevisionPlaceSource]
    public init(draftID: UUID, parentRevisionID: UUID, plan: DynamicPlanInput, requiredPlaceIDs: [String], sources: [RevisionPlaceSource]) {
        self.draftID = draftID; self.parentRevisionID = parentRevisionID; self.plan = plan; self.requiredPlaceIDs = requiredPlaceIDs; self.sources = sources
    }
    public func result(for response: DynamicPlanResponse) -> PersonalPlanResult {
        let trip = response.itinerary
        let visited = Set(trip.visits.map(\.placeID))
        let omitted = sources.map(\.placeID).filter { !visited.contains($0) }.map { id in
            let context = trip.contexts.first { $0.placeID == id }
            let reason: String
            if let context, context.options.isEmpty { reason = "Konteks kunjungan belum memenuhi syarat: " + context.status }
            else if trip.status == "incomplete_travel_data" { reason = "Bukti perjalanan belum lengkap dalam pencarian ini; periksa provider atau rute." }
            else { reason = "Belum terpilih dalam batas pencarian dan batas perjalanan; bukan bukti global tidak memungkinkan." }
            return PersonalPlanOmission(id: id, required: requiredPlaceIDs.contains(id), reason: reason)
        }
        return .init(result: response, requiredPlaceIDs: requiredPlaceIDs, omitted: omitted, momentReview: nil)
    }
    public func validate(placeIDs: [String]) throws {
        guard plan.order == .fixed, !placeIDs.isEmpty, placeIDs.count <= 6, Set(placeIDs).count == placeIDs.count,
              Set(requiredPlaceIDs).count == requiredPlaceIDs.count, Set(requiredPlaceIDs).isSubset(of: Set(placeIDs)),
              sources.count == placeIDs.count, sources.map(\.placeID) == placeIDs else { throw ContextError.invalid("Draft/order/provenance mismatch") }
    }
}
public struct ItineraryRevisionPreview: Codable, Sendable {
    public var draftID: UUID
    public var parentRevisionID: UUID
    public var generatedAt: Date
    public var result: PersonalPlanResult
    public var sources: [RevisionPlaceSource]
    public var canApply: Bool
    public init(input: ItineraryRevisionInput, result: PersonalPlanResult, generatedAt: Date = .now) {
        draftID = input.draftID; parentRevisionID = input.parentRevisionID; self.generatedAt = generatedAt
        self.result = result; sources = input.sources
        let trip = result.result.itinerary
        let ordered = input.sources.map(\.placeID)
        let visited = trip.visits.map(\.placeID)
        let retained = ordered.filter { visited.contains($0) }
        canApply = trip.status.hasPrefix("candidate") && !visited.isEmpty && visited == retained &&
            Set(input.requiredPlaceIDs).isSubset(of: Set(visited)) && trip.finish.map { $0 <= input.plan.deadline } == true &&
            trip.legs.count == visited.count + 1 && trip.legs.first?.departure == input.plan.departure &&
            trip.totalWaitingSeconds <= Double(input.plan.maximumWaitingMinutes * 60) + 0.001
    }
}
