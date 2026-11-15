import Foundation
import PreferenceQuality
import PreferenceLearning

public enum LabVariant: String, Codable, Sendable { case B, C, D, E }
public enum LabProviderMode: String, Codable, Sendable { case replay, rest }
public struct LabOutcome: Codable, Sendable {
    public var outcome: String
    public var plan: IntegratedPlan?
    public var review: RecommendationReview?
    public var prepared: PreparedTrip?
    public var lowerBoundSeconds: Double?
    public var availableSeconds: Double?
    public var providerMetrics: LabProviderMetrics
    public var elapsedSeconds: Double
    public var evidence: String
    public init(outcome: String, plan: IntegratedPlan? = nil, review: RecommendationReview? = nil,
                prepared: PreparedTrip? = nil, lowerBoundSeconds: Double? = nil, availableSeconds: Double? = nil,
                providerMetrics: LabProviderMetrics = .init(), elapsedSeconds: Double, evidence: String) {
        self.outcome = outcome; self.plan = plan; self.review = review; self.prepared = prepared
        self.lowerBoundSeconds = lowerBoundSeconds; self.availableSeconds = availableSeconds
        self.providerMetrics = providerMetrics; self.elapsedSeconds = elapsedSeconds; self.evidence = evidence
    }
}
@MainActor public final class LabRuntime {
    public let catalog: IntegrationCatalog
    let baseEmbedding = LabE5Embedding()
    let optimizedEmbedding: LabEmbeddingCache
    public init(embeddingDirectory: URL) throws {
        catalog = try .load()
        optimizedEmbedding = LabEmbeddingCache(directory: embeddingDirectory, runtime: baseEmbedding,
                                               areaIDs: Dictionary(grouping: catalog.quality.candidates, by: \.passage).mapValues { $0.map(\.id).sorted().joined(separator: ",") })
    }
    public func precompute() async throws -> Double {
        let start = ContinuousClock.now
        _ = try await optimizedEmbedding.metadata()
        for candidate in catalog.quality.candidates { _ = try await optimizedEmbedding.encode(candidate.passage, query: false) }
        return Self.seconds(start)
    }
    public func run(_ request: TripRequest, variant: LabVariant, mode: LabProviderMode,
                    now: Date, directory: URL, baseAcceptedID: UUID? = nil,
                    eta: (any LabETAProvider)? = nil, search: (any TripPlaceSearching)? = nil,
                    weather: (any TripWeatherFetching)? = nil,
                    progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws -> LabOutcome {
        let began = ContinuousClock.now
        try request.validate(catalog: catalog, now: now)
        if mode == .rest && (eta == nil || search == nil || weather == nil) {
            throw IntegrationError.invalid("REST credentials/providers not configured; no native or mock fallback")
        }
        let provider: any LabETAProvider = eta ?? LabOracle()
        let acquisition = LabAcquisition(provider)
        let embedding: any PreferenceEmbedding = variant != .B ? optimizedEmbedding : baseEmbedding
        let pipeline = IntegrationPipeline(catalog: catalog, quality: QualityPipeline(embedding: embedding),
                                           search: search ?? ReplaySearch(), weather: TripWeatherCoordinator(provider: weather ?? ReplayWeather()),
                                           logDirectory: directory.appendingPathComponent("ProviderLogs"))
        pipeline.labFast = variant == .D
        pipeline.labSelective = variant == .E
        pipeline.labBulk = variant == .C
        pipeline.labIsREST = mode == .rest
        pipeline.replayETA = { from, to, m, date in
            let query = LabETAQuery(fromID: from.id, toID: to.id, fromLatitude: from.latitude!,
                                    fromLongitude: from.longitude!, toLatitude: to.latitude!, toLongitude: to.longitude!,
                                    mode: m.rawValue, departure: date)
            return try await acquisition.fetch([query], bulk: false)[0].native
        }
        pipeline.labBatch = { try await acquisition.fetch($0, bulk: true) }
        let review = try await pipeline.recommend(request, now: now) { message in await progress(message) }
        let ids = Set(request.requiredCandidateIDs + review.suggestions.filter(\.recommended).map(\.id))
        let chosen = review.suggestions.filter { ids.contains($0.id) }
        func outcome(_ state: String, plan: IntegratedPlan? = nil, prepared: PreparedTrip? = nil,
                     lower: Double? = nil) -> LabOutcome {
            .init(outcome: state, plan: plan, review: review, prepared: prepared,
                  lowerBoundSeconds: lower, availableSeconds: lower == nil ? nil : request.deadline.timeIntervalSince(request.departure),
                  providerMetrics: provider.metrics, elapsedSeconds: Self.seconds(began),
                  evidence: mode == .replay ? "synthetic_replay" : "live_rest")
        }
        guard (1 ... 6).contains(ids.count), chosen.count == ids.count,
              ids.count >= max(request.desiredCount, request.requiredCandidateIDs.count),
              Set(chosen.map(\.venueID)).count == chosen.count,
              Set(request.requiredCandidateIDs).isSubset(of: ids), chosen.allSatisfy(\.selectable)
        else { return outcome("needs_places") }
        let lower = chosen.reduce(0.0) { $0 + Double(request.duration($1.venueID) * 60) }
        if variant != .B, lower > request.deadline.timeIntervalSince(request.departure) {
            return outcome("infeasible_lower_bound", lower: lower)
        }
        let selectedIDs = chosen.map(\.id)
        let prepared = try await pipeline.prepare(review, selectedIDs: selectedIDs, now: now, progress: progress)
        guard prepared.ready else { return outcome("needs_locations", prepared: prepared) }
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: baseAcceptedID,
                                           now: now, progress: progress)
        if plan.feasible { try PlanAudit.validate(plan); return outcome("ready", plan: plan, prepared: prepared) }
        let missing = plan.legs.contains { $0.providerStatus != "available" || $0.seconds == nil }
        let allFailed = provider.metrics.cells > 0 && provider.metrics.failures == provider.metrics.cells
        return outcome(allFailed ? "provider_unavailable" : missing ? "incomplete_data" : "no_feasible_candidate",
                       plan: plan, prepared: prepared)
    }
    static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
