import Foundation

/// D v1: local surrogate search, then a bounded number of provider validations.
/// Surrogate values never enter NativeTripAppleServices' ETA cache or returned legs.
@MainActor enum LabFastPlanner {
    static let maximumValidations = 3
    struct Estimate {
        var order: [NativeTripStop]
        var finish: Date
        var travelSeconds: Double
        var conflicts: Int
        var risk: Double
        var score: Double { finish.timeIntervalSince1970 + risk }
    }
    static func permutations(_ values: [NativeTripStop]) -> [[NativeTripStop]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index -> [[NativeTripStop]] in
            var rest = values; let first = rest.remove(at: index)
            return permutations(rest).map { [first] + $0 }
        }
    }
    static func estimate(_ order: [NativeTripStop], draft: NativeTripDraft,
                         visitStart: ((String, Date) -> Date?)?, forecasts: [NativeTripForecast],
                         calibratedEdges: [String: Double] = [:]) -> Estimate {
        var cursor = draft.departure; var from = draft.origin
        var travel = 0.0; var conflicts = 0; var risk = 0.0
        for stop in order + [NativeTripStop(point: draft.endPoint, role: .transfer)] {
            let minute = draft.calendar.component(.hour, from: cursor) * 60 + draft.calendar.component(.minute, from: cursor)
            let peak = (420 ..< 600).contains(minute) || (960 ..< 1140).contains(minute)
            // An uncalibrated prior, deliberately labelled as an estimate, not a real ETA.
            let seconds = calibratedEdges[from.id + ">" + stop.id]
                ?? (300 + from.distance(to: stop.point) / 8) * (peak ? 1.35 : 1)
            travel += seconds; cursor.addTimeInterval(seconds)
            if stop.role == .visit {
                if let opens = stop.opening?.opensMinute { cursor = max(cursor, draft.clockDate(minutes: opens)) }
                if let visitStart {
                    if let allowed = visitStart(stop.id, cursor) { cursor = allowed } else { conflicts += 1 }
                }
                let leave = cursor.addingTimeInterval(Double(stop.dwell(defaultMinutes: draft.defaultDwell)) * 60)
                if let closes = stop.opening?.closesMinute, leave > draft.clockDate(minutes: closes) { conflicts += 1 }
                if let factor = stop.exposure.factor, let forecast = forecasts.first(where: { $0.pointID == stop.id }) {
                    for hour in forecast.hours {
                        let overlap = max(0, min(leave, hour.date.addingTimeInterval(3600)).timeIntervalSince(max(cursor, hour.date)))
                        risk += overlap * hour.rainChance * factor * draft.rainWeight
                    }
                }
                cursor = leave
            }
            from = stop.point
        }
        if cursor > draft.deadline { conflicts += 1 }
        return .init(order: order, finish: cursor, travelSeconds: travel, conflicts: conflicts, risk: risk)
    }
    static func ranked(_ a: Estimate, _ b: Estimate) -> Bool {
        if a.conflicts != b.conflicts { return a.conflicts < b.conflicts }
        if a.score != b.score { return a.score < b.score }
        if a.travelSeconds != b.travelSeconds { return a.travelSeconds < b.travelSeconds }
        return a.order.map(\.id).lexicographicallyPrecedes(b.order.map(\.id))
    }
    static func plan(_ draft: NativeTripDraft, services: NativeTripAppleServices,
                     progress: (String) -> Void) async throws -> NativeTripReport {
        try draft.validate()
        guard draft.stops.count <= 6, draft.modes == [.automobile], !draft.usesPrivateCar else {
            throw IntegrationError.invalid("D v1 supports at most six destinations, on-demand automobile only")
        }
        let started = ContinuousClock.now
        services.resetRun()
        let forecasts = try await services.forecasts(points: draft.allPoints, draft: draft, progress: progress)
        let orders = permutations(draft.stops)
        var candidates: [NativeTripCandidate] = []
        var checked = Set<[String]>()
        var calibration: [String: Double] = [:]
        var localEvaluations = 0
        for attempt in 1 ... maximumValidations {
            try Task.checkCancellation()
            let estimates = orders.filter { !checked.contains($0.map(\.id)) }.map {
                estimate($0, draft: draft, visitStart: services.integrationVisitStart,
                         forecasts: forecasts, calibratedEdges: calibration)
            }
            localEvaluations += estimates.count
            guard let chosen = estimates.min(by: ranked) else { break }
            let signature = chosen.order.map(\.id); checked.insert(signature)
            services.event("routing.fast_surrogate", category: "optimizer", fields: [
                "policy": "D-v1-distance-prior-3-validation", "estimatedOnly": "true",
                "localOrders": String(estimates.count), "attempt": String(attempt),
                "order": signature.joined(separator: "/"), "estimatedConflicts": String(chosen.conflicts),
                "estimatedElapsedSeconds": String(chosen.finish.timeIntervalSince(draft.departure)),
                "calibrationEdges": String(calibration.count)])
            progress("D · validating finalist \(attempt)/\(maximumValidations), local orders \(estimates.count)")
            let candidate = try await NativeTripEngine.evaluate(chosen.order, draft: draft,
                                                                services: services, forecasts: forecasts, progress: progress)
            candidates.append(candidate)
            services.logs.recordJSON("routing.fast_validated_candidate", category: "optimizer",
                                     operationID: services.operationID, value: candidate)
            if candidate.feasible { break }
            // Calibration informs speculative ranking only. Final-leg evidence still comes from exact-time calls.
            for leg in candidate.legs {
                if let seconds = leg.chosen?.seconds, leg.chosen?.usable == true {
                    calibration[leg.from.id + ">" + leg.to.id] = seconds
                }
            }
            if candidate.legs.contains(where: { $0.chosen?.usable != true }) { break }
        }
        let best = candidates.sorted(by: NativeTripCandidate.better).first
        let elapsed = started.duration(to: .now).components
        services.event("routing.pipeline_completed", category: "optimizer", fields: [
            "objective": "elapsed_v2", "policy": "D-v1-distance-prior-3-validation",
            "candidateCount": String(candidates.count), "localEvaluations": String(localEvaluations),
            "requests": String(services.directionRequests),
            "elapsedSeconds": String(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)])
        return .init(draft: draft, candidates: candidates, fastest: best, weatherChoice: nil,
                     forecasts: forecasts, requests: services.directionRequests,
                     weatherNote: "Weather informs local shortlist; only provider-validated finalist is returned.",
                     optimizerNote: "D v1 · uncalibrated distance/time prior, up to 3 validations, first feasible. Approximate search can lose objective quality; no optimality or C-parity claim.")
    }
}
