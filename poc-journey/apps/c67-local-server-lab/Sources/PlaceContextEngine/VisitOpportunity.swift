import Foundation

/// A sourced opportunity to spend time at a place within a specific interval.
public struct VisitOpportunity: Codable, Sendable {
    public var id: String
    public var placeID: String
    public var start: Date
    public var end: Date
    public var minimumMinutes: Int
    public var sourceName: String
    public var sourceURL: URL
    public var forecastCheckedAt: Date

    public init(id: String, placeID: String, start: Date, end: Date, minimumMinutes: Int,
                sourceName: String, sourceURL: URL, forecastCheckedAt: Date) {
        self.id = id
        self.placeID = placeID
        self.start = start
        self.end = end
        self.minimumMinutes = minimumMinutes
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.forecastCheckedAt = forecastCheckedAt
    }

    public func matches(_ visit: VisitContextOption) -> Bool {
        minimumMinutes > 0 && min(end, visit.end).timeIntervalSince(max(start, visit.start)) >= Double(minimumMinutes * 60)
    }

    public func matches(_ itinerary: ContextItineraryResult) -> Bool {
        itinerary.visits.contains { $0.placeID == placeID && matches($0.visit) }
    }
}

public struct OpportunityItineraries: Sendable {
    public var baseline: ContextItineraryResult
    public var baselineMoment: VisitOpportunity?
    public var alternative: ContextItineraryResult?
    public var alternativeMoment: VisitOpportunity?
}

@MainActor public enum OpportunityItineraryPlanner {
    public static func plan(_ input: ContextPlanRequest, requiredIDs: Set<String>,
                            moments: [VisitOpportunity], provider: any ContextTravelProvider, now: Date = .now) async throws -> OpportunityItineraries {
        let candidates = try moments.filter { moment in
            guard let stop = input.stops.first(where: { $0.request.placeID == moment.placeID }),
                  stop.request.preferredTime == nil else { return false }
            return try VisitContextEngine.evaluate(snapshot: stop.snapshot, request: stop.request,
                                                   weather: stop.weather, now: now).options.contains(where: moment.matches)
        }

        guard !candidates.isEmpty else {
            let result = try await OptionalItineraryPlanner.plan(input, requiredIDs: requiredIDs, provider: provider, now: now)
            return .init(baseline: result)
        }

        // The regular route gets its original budget. An alternative can only use
        // leftover calls and the exact-departure evidence already collected.
        let total = input.maxTravelCalls
        let memo = ContextTravelMemo(base: provider, limit: total)
        let baseline = try await OptionalItineraryPlanner.plan(input, requiredIDs: requiredIDs, provider: memo, now: now)
        let baselineMoment = candidates.first { $0.matches(baseline) }
        var result = OpportunityItineraries(baseline: baseline, baselineMoment: baselineMoment)
        if baselineMoment == nil, !baseline.visits.isEmpty, memo.calls < total {
            let retained = Set(baseline.visits.map(\.placeID))
            if let moment = candidates.first(where: { retained.contains($0.placeID) }) {
                var alternativeInput = input
                alternativeInput.stops = input.stops.filter { retained.contains($0.request.placeID) }
                alternativeInput.maxTravelCalls = total
                do {
                    var alternative = try await ContextItineraryPlanner.plan(alternativeInput, provider: memo,
                                                                             now: now, requiring: moment)
                    if moment.matches(alternative), Set(alternative.visits.map(\.placeID)) == retained,
                       zip(alternative.penaltyByPriority, baseline.penaltyByPriority).allSatisfy({ $0 <= $1 }),
                       extraEffort(alternative, over: baseline) <= 15 * 60 {
                        alternative.contexts = baseline.contexts
                        alternative.travelCalls = memo.calls
                        result.alternative = alternative
                        result.alternativeMoment = moment
                    }
                } catch {
                    try Task.checkCancellation()
                    result.baseline.warnings.append("Alternatif momen belum dapat diperiksa; jadwal utama tetap tersedia")
                }
            }
        }
        result.baseline.travelCalls = memo.calls
        return result
    }

    private static func extraEffort(_ alternative: ContextItineraryResult, over baseline: ContextItineraryResult) -> Double {
        max(0, alternative.travelSeconds - baseline.travelSeconds) + max(0, alternative.waitingSeconds - baseline.waitingSeconds)
    }
}
