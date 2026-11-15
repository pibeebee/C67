import Foundation
import PreferenceQuality

/// Inputs only. Reviewer judgments are deliberately owned by the external evaluator.
public struct BlokMPersona: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var profile: QualityProfile
    public var heldOut: Bool
}

public struct BlokMRecommendationRun: Codable, Sendable {
    public var persona: BlokMPersona
    public var window: String
    public var method: String
    public var displayedIDs: [String]
    public var eligibleIDs: [String]
    public var factSupportedIDs: [String]
    public var review: RecommendationReview
}

@MainActor public enum BlokMExperiment {
    public static var personas: [BlokMPersona] {
        func persona(_ id: String, _ title: String, prefer: Set<QualityFeature> = [],
                     avoid: Set<QualityFeature> = [], heldOut: Bool = false) -> BlokMPersona {
            var profile = QualityProfile()
            profile.prefer = prefer
            profile.avoid = avoid
            return .init(id: id, title: title, profile: profile, heldOut: heldOut)
        }
        return [
            persona("P0", "General profile"),
            persona("P1", "Coffee and Wi-Fi", prefer: [.coffee, .wifi]),
            persona("P2", "Reading and a silent-zone policy", prefer: [.reading, .quietPolicy]),
            persona("P3", "Art and culture", prefer: [.art, .culture]),
            persona("P4", "Outdoor and nature", prefer: [.outdoor, .nature], heldOut: true),
            persona("P5", "Coffee, avoiding smoking areas", prefer: [.coffee], avoid: [.smokingArea], heldOut: true),
        ]
    }

    public static func snapshotClock(_ catalog: IntegrationCatalog) -> Date {
        catalog.quality.sources.map(\.checkedAt).max()!.addingTimeInterval(1)
    }

    public static func request(now: Date, afternoon: Bool = false) -> TripRequest {
        var value = TripRequest(now: now)
        let tomorrow = TripClock.calendar.date(byAdding: .day, value: 1, to: now)!
        value.departure = TripClock.calendar.date(bySettingHour: afternoon ? 14 : 9, minute: 0, second: 0, of: tomorrow)!
        value.deadline = TripClock.calendar.date(bySettingHour: afternoon ? 21 : 19, minute: 0, second: 0, of: tomorrow)!
        value.useEmbedding = false
        return value
    }

    /// The general comparator retains its own ordering but shares the target's factual/time gates.
    /// This avoids crediting personalization solely for enforcing a hard restriction.
    public static func generalIDs(general: RecommendationReview, target: RecommendationReview) -> [String] {
        let eligible = Set(target.suggestions.filter(\.selectable).map(\.id))
        var venues = Set<String>()
        return general.suggestions.filter {
            eligible.contains($0.id) && venues.insert($0.venueID).inserted
        }.prefix(target.request.desiredCount).map(\.id)
    }

    public static func recommendations(catalog: IntegrationCatalog, now: Date, useEmbedding: Bool,
                                       includeHeldOut: Bool = false) async throws -> [BlokMRecommendationRun] {
        let pipeline = IntegrationPipeline(catalog: catalog)
        var runs: [BlokMRecommendationRun] = []
        for afternoon in [false, true] {
            let base = request(now: now, afternoon: afternoon)
            let general = try await pipeline.recommend(base, now: now)
            for persona in personas where includeHeldOut || !persona.heldOut {
                var input = base
                input.profile = persona.profile
                let category = try await pipeline.recommend(input, now: now)
                let eligible = category.suggestions.filter(\.selectable).map(\.id)
                let desired = persona.profile.must.union(persona.profile.softFeatures)
                let supported = eligible.filter { id in
                    guard let candidate = catalog.candidate(id) else { return false }
                    return desired.contains { candidate.value($0) == .yes }
                }
                func row(_ method: String, _ review: RecommendationReview, ids: [String]) -> BlokMRecommendationRun {
                    .init(persona: persona, window: afternoon ? "afternoon" : "day", method: method,
                          displayedIDs: ids, eligibleIDs: eligible, factSupportedIDs: supported, review: review)
                }
                runs.append(row("general", general, ids: generalIDs(general: general, target: category)))
                runs.append(row("category", category, ids: category.suggestions.filter(\.recommended).map(\.id)))
                if useEmbedding {
                    input.useEmbedding = true
                    let combined = try await pipeline.recommend(input, now: now)
                    runs.append(row("combined", combined, ids: combined.suggestions.filter(\.recommended).map(\.id)))
                }
            }
        }
        return runs
    }
}
