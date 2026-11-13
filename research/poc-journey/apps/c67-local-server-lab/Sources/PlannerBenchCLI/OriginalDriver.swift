import Foundation
@testable import TripIntegration
import PlannerContracts

/// Runs the exact original UI orchestration, in its own module, with the shared explicit oracle.
@MainActor final class OriginalDriver {
    private var baseline: IntegrationModel?
    private var baselineOracle: LabOracle?
    private var pendingBaseline: IntegrationModel?
    private var pendingOracle: LabOracle?
    private var lastPipeline: TripIntegration.IntegrationPipeline?
    private var lastOracle: LabOracle?
    func acceptBaseline() async throws {
        guard let model = pendingBaseline else { return }
        model.apply()
        while model.busy || model.saving { try await Task.sleep(for: .milliseconds(10)) }
        if let error = model.error { throw LabFailure.conflict(error) }
        baseline = model; baselineOracle = pendingOracle
        pendingBaseline = nil; pendingOracle = nil
    }
    func run(_ input: PlannerEngine.TripRequest, now: Date, directory: URL,
             revision: Bool = false, replay: Bool = true, reusePipeline: Bool = false, pinSnapshot: LabPinSnapshot? = nil) async throws -> LabOutcome {
        let request = try LabJSON.decoder().decode(TripIntegration.TripRequest.self, from: LabJSON.encoder().encode(input))
        let oracle = revision ? (baselineOracle ?? LabOracle()) : reusePipeline ? (lastOracle ?? LabOracle()) : LabOracle()
        let before = oracle.metrics
        let pipeline = reusePipeline ? lastPipeline! : replay ? TripIntegration.IntegrationPipeline(catalog: try .load(), search: TripIntegration.ReplaySearch(),
                                                                                                    weather: TripIntegration.TripWeatherCoordinator(provider: TripIntegration.ReplayWeather()),
                                                                                                    logDirectory: directory.appendingPathComponent("ProviderLogs"))
            : TripIntegration.IntegrationPipeline(catalog: try .load(),
                                                  search: pinSnapshot != nil ? try OriginalPinnedSearch(snapshot: pinSnapshot!) : TripIntegration.MapKitTripSearch(),
                                                  logDirectory: directory.appendingPathComponent("ProviderLogs"))
        if replay, !reusePipeline { pipeline.replayETA = { a, b, mode, departure in
            let query = LabETAQuery(fromID: a.id, toID: b.id, fromLatitude: a.latitude!, fromLongitude: a.longitude!,
                                    toLatitude: b.latitude!, toLongitude: b.longitude!, mode: mode.rawValue, departure: departure)
            let v = try await oracle.values([query])[0]
            return TripIntegration.NativeTripETA(id: "\(a.id)>\(b.id)", mode: mode, seconds: v.seconds, distance: v.distance,
                                                 expectedDeparture: departure, expectedArrival: v.seconds.map { departure.addingTimeInterval($0) },
                                                 status: v.status, note: v.note)
        }
        }
        if !reusePipeline { lastPipeline = pipeline; lastOracle = oracle }
        let model: IntegrationModel
        if revision, let old = baseline { model = old }
        else {
            model = IntegrationModel(catalog: try .load(), pipeline: pipeline,
                                     store: TripIntegration.TripStore(directory: directory.appendingPathComponent("Session")),
                                     request: request, replay: replay, clock: { replay ? now : .now })
            await model.load()
        }
        let start = ContinuousClock.now
        if revision {
            guard let plan = model.session.accepted, let stop = plan.stops.last else { throw LabFailure.conflict("A revision baseline missing") }
            model.extendAutomatically(stop, plan: plan)
        } else { model.createItinerary() }
        do {
            while model.busy || model.saving {
                if start.duration(to: .now) > .seconds(240) { model.cancel(); throw LabFailure.unavailable("A observation limit") }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch { model.cancel(); throw error }
        if let error = model.error { throw LabFailure.unavailable(error) }
        func convert<T: Decodable, U: Encodable>(_ value: U?, as: T.Type) throws -> T? {
            guard let value else { return nil }; return try LabJSON.decoder().decode(T.self, from: LabJSON.encoder().encode(value))
        }
        let plan: PlannerEngine.IntegratedPlan? = try convert(model.session.proposal, as: PlannerEngine.IntegratedPlan.self)
        let review: PlannerEngine.RecommendationReview? = try convert(model.review, as: PlannerEngine.RecommendationReview.self)
        let prepared: PlannerEngine.PreparedTrip? = try convert(model.prepared, as: PlannerEngine.PreparedTrip.self)
        var state = model.simpleStep == .needsPlaces ? "needs_places" : model.simpleStep == .needsLocations ? "needs_locations"
            : plan?.feasible == true ? "ready" : "no_feasible_candidate"
        if !revision, input.requiredCandidateIDs.count == 5, plan?.feasible == true {
            pendingBaseline = model; pendingOracle = oracle
        }
        var metrics = oracle.metrics
        metrics.calls -= before.calls; metrics.cells -= before.cells; metrics.failures -= before.failures
        metrics.requests = Array(metrics.requests.dropFirst(before.requests.count))
        if !replay {
            metrics.calls = plan?.metrics.filter { $0.stage == "mapkit_eta" }.reduce(0) { $0 + $1.requests } ?? 0
            metrics.cells = metrics.calls
            if let log = plan?.providerLog, let text = String(data: log, encoding: .utf8) {
                let events = text.split(separator: "\n").compactMap {
                    try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                }
                let sessionID = events.last { $0["event"] as? String == "routing.pipeline_completed" }?["sessionID"] as? String
                let scoped = events.filter { $0["sessionID"] as? String == sessionID }
                let failed = scoped.filter { event in
                    guard event["event"] as? String == "eta.result", let f = event["fields"] as? [String: String] else { return false }
                    return f["source"] == "provider" && f["status"] != "available"
                }
                metrics.failures = failed.count
                metrics.cacheHits = scoped.filter { ($0["event"] as? String) == "eta.result"
                    && (($0["fields"] as? [String: String])?["source"] == "cache") }.count
            }
            if plan?.feasible != true, metrics.cells > 0 {
                if metrics.failures == metrics.cells { state = "provider_unavailable" }
                else if plan?.legs.contains(where: { $0.providerStatus != "available" || $0.seconds == nil }) == true { state = "incomplete_data" }
            }
        }
        return LabOutcome(outcome: state, plan: plan, review: review, prepared: prepared,
                          providerMetrics: metrics, elapsedSeconds: elapsed(start), evidence: replay ? "synthetic_replay_original_A" : pinSnapshot == nil ? "live_native" : "live_native_shared_real_pins")
    }
}
func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let c = start.duration(to: .now).components; return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

@MainActor private final class OriginalPinnedSearch: TripIntegration.TripPlaceSearching {
    let snapshot: LabPinSnapshot
    init(snapshot: LabPinSnapshot) throws { try snapshot.validate(now: .now); self.snapshot = snapshot }
    func cancel() {}
    func search(query: String) async throws -> [TripIntegration.PlacePin] {
        try Task.checkCancellation()
        guard let id = snapshot.queries[query], let pin = snapshot.pins[id] else { throw LabFailure.invalid("Shared pin snapshot missing native query") }
        return [try LabJSON.decoder().decode(TripIntegration.PlacePin.self, from: LabJSON.encoder().encode(pin))]
    }
}
