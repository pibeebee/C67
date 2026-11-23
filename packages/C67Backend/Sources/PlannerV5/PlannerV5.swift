import C67Domain
import Foundation

public struct PlannerV5: Sendable {
    public typealias RouteProvider = @Sendable (PlanningPoint, PlanningPoint, Date, PlanningMode) async throws -> PlannerV5Route?

    let route: RouteProvider
    let checkInBufferMinutes: Int?

    public init(route: @escaping RouteProvider) {
        self.init(route: route, checkInBufferMinutes: nil)
    }

    init(route: @escaping RouteProvider, checkInBufferMinutes: Int?) {
        self.route = route
        self.checkInBufferMinutes = checkInBufferMinutes
    }

    public func plan(_ input: PlannerV5Input) async throws -> PlannerV5Result {
        var work = Work()
        return try await solve(input, work: &work)
    }

    /// Reuses the original routing cache and remaining budgets for one refinement of this work.
    public func prepare(_ input: PlannerV5Input) async throws -> PlannerV5PreparedPlan {
        var work = Work()
        let result = try await solve(input, work: &work)
        return PlannerV5PreparedPlan(result: result, planner: self, input: input, work: work)
    }

    func solve(_ input: PlannerV5Input, work: inout Work) async throws -> PlannerV5Result {
        try input.trip.validate(purpose: .firstItinerary)
        let trip = input.trip
        guard (1 ... 6).contains(trip.places.count), (0 ... 1440).contains(input.extraTravelMinutes),
              Set(input.visits.keys).isSubset(of: Set(trip.places.map(\.id))),
              [trip.startsAt, trip.finishBy].allSatisfy({ abs($0.timeIntervalSince1970) < 1e12 }),
              (0 ... 1440).contains(trip.enginePreferences?.maximumWaitMinutes ?? 0),
              checkInBufferMinutes == nil ||
                  (0 ... 1440).contains(input.checkInBufferMinutes ?? checkInBufferMinutes ?? 0) else {
            throw PlannerV5Error.invalidInput
        }
        let day = try Day(input)
        let durations = day.stops.map { $0.duration.target }
        let base = try await search(day, durations: durations, work: &work)
        var sensitivity: [PlannerV5Sensitivity] = []
        var requests: [PlannerV5EnrichmentRequest] = []
        var sensitivityLimited = false

        for (index, stop) in day.stops.enumerated() where stop.duration.minutes.lowerBound < stop.duration.minutes.upperBound {
            let options = sensitivityMinutes(day, index: index, schedule: base.selected)
            for value in options where value != durations[index] {
                // Keep some capacity for an optional refinement when the sensitivity fan-out is large.
                guard work.limit == nil, work.quotes < 54, work.candidates < 400 else {
                    sensitivityLimited = true
                    break
                }
                var trialDurations = durations
                trialDurations[index] = value
                let trial = try await search(day, durations: trialDurations, work: &work)
                let order = trial.selected?.visits.map(\.placeID)
                sensitivity.append(.init(placeID: stop.place.id, minutes: value, recommendedOrder: order,
                                         metrics: trial.selected?.metrics ?? [], status: trial.status, issues: trial.issues))
                if trial.status == .incomplete || trial.partial { sensitivityLimited = true }
                if trial.status != .incomplete, base.status != .incomplete,
                   order != base.selected?.visits.map(\.placeID) || trial.status != base.status {
                    let kind: PlannerV5Information = stop.context.activity == nil ? .activitySuggestion : .travellerIntent
                    append(.init(placeID: stop.place.id, information: kind), to: &requests)
                }
            }
        }
        if base.selected == nil, base.status == .conflicts {
            for stop in day.stops where stop.access?.source != .traveller && base.issues.contains(.access(stop.place.id)) {
                append(.init(placeID: stop.place.id, information: .venueAccess), to: &requests)
            }
        }
        for id in base.uncertainExposure {
            append(.init(placeID: id, information: .travellerIntent), to: &requests)
        }

        let reason: String
        if checkInBufferMinutes != nil, let selected = base.selected {
            let limited = selected.checkIns.filter { $0.shortfallMinutes > 0 }.count
            reason = limited > 0
                ? "The recommended schedule meets the check-in deadlines. \(limited) check-in buffer targets fall short."
                : "The schedule balances check-in buffers and comparable outdoor conditions within the travel allowance."
        } else if let selected = base.selected {
            let conditional = sensitivity.contains { sample in
                sample.status == .scheduled && selected.metrics.contains { metric in
                    sample.metrics.first { $0.placeID == metric.placeID && $0.goal == metric.goal }?.value != metric.value
                }
            }
            reason = conditional
                ? "The schedule uses the shown visit durations. Environmental benefits vary across the checked durations."
                : "The schedule was selected from checked candidates using access, traveller preferences and travel estimates."
        } else if base.status == .conflicts {
            reason = "The checked scheduling domain has conflicts under the supplied constraints and visit durations."
        } else {
            reason = "The search ended before a complete schedule could be established."
        }
        return .init(status: base.status, schedule: base.selected, fastestComparable: base.fastest,
                     alternative: base.alternative, issues: base.issues,
                     enrichment: requests, sensitivity: sensitivity,
                     limit: work.limit ?? (base.missingETA ? .unavailableETA : (base.partial ? .shortlist : (sensitivityLimited ? .sensitivity : nil))),
                     routeQuotes: work.quotes, evaluatedCandidates: work.candidates, completeCandidates: base.completeCandidates, reason: reason)
    }

    private func append(_ request: PlannerV5EnrichmentRequest, to requests: inout [PlannerV5EnrichmentRequest]) {
        if !requests.contains(request) { requests.append(request) }
    }
}

/// A refinement owns the remaining search budget and can be submitted once.
public actor PlannerV5PreparedPlan {
    public nonisolated let result: PlannerV5Result
    private let planner: PlannerV5
    private let input: PlannerV5Input
    private var work: PlannerV5.Work?

    init(result: PlannerV5Result, planner: PlannerV5, input: PlannerV5Input, work: PlannerV5.Work) {
        self.result = result
        self.planner = planner
        self.input = input
        self.work = work
    }

    public func refine(with answers: [PlannerV5EnrichmentAnswer]) async throws -> PlannerV5Result {
        guard var work else { throw PlannerV5Error.invalidEnrichment }
        if answers.isEmpty { return result }
        var updated = input
        var consumed: [PlannerV5EnrichmentRequest] = []
        for answer in answers {
            let request: PlannerV5EnrichmentRequest
            switch answer {
            case let .traveller(id, _, _, _): request = .init(placeID: id, information: .travellerIntent)
            case let .venue(id, _): request = .init(placeID: id, information: .venueAccess)
            case let .suggestion(id, _, _, _): request = .init(placeID: id, information: .activitySuggestion)
            }
            let alternate = PlannerV5EnrichmentRequest(placeID: request.placeID, information: .activitySuggestion)
            let matched = result.enrichment.contains(request) ? request : alternate
            guard result.enrichment.contains(matched),
                  matched == request || request.information == .travellerIntent,
                  !consumed.contains(matched),
                  let place = input.trip.places.first(where: { $0.id == request.placeID }) else {
                throw PlannerV5Error.invalidEnrichment
            }
            consumed.append(matched)
            var context = updated.visits[place.id] ?? .init()
            switch answer {
            case let .traveller(_, activity, minutes, exposure):
                if let activity { context.activity = activity; context.activitySource = .traveller }
                if let minutes {
                    guard (1 ... 1440).contains(minutes), !place.hasExplicitVisitDuration else {
                        throw PlannerV5Error.invalidEnrichment
                    }
                    context.duration = .init(minutes: minutes ... minutes, target: minutes, source: .traveller)
                }
                if let exposure { context.exposure = exposure; context.exposureSource = .traveller }
            case let .venue(_, access):
                guard case .venue = access.source else { throw PlannerV5Error.invalidEnrichment }
                context.access = access
            case let .suggestion(_, activity, duration, source):
                if let activity, context.activity == nil {
                    context.activity = activity
                    context.activitySource = .suggestion(source)
                }
                if var duration, !place.hasExplicitVisitDuration, context.duration?.source != .traveller {
                    duration.source = .suggestion(source)
                    context.duration = duration
                }
            }
            updated.visits[place.id] = context
        }
        _ = try PlannerV5.Day(updated)
        work.limit = nil
        self.work = nil
        do {
            return try await planner.solve(updated, work: &work)
        } catch {
            self.work = work
            throw error
        }
    }
}
