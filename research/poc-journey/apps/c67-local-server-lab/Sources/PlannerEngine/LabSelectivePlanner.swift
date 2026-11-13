import Foundation

/// E: experimental uncertainty-triggered validation. Estimates never become final ETAs.
/// A bounded exploration policy, not an optimum certificate or trained traffic model.
@MainActor enum LabSelectivePlanner {
    static func plan(_ draft: NativeTripDraft, services: NativeTripAppleServices,
                     maximumValidations: Int = 3, progress: (String) -> Void) async throws -> NativeTripReport {
        try draft.validate()
        guard draft.stops.count <= 6, draft.modes == [.automobile], !draft.usesPrivateCar,
              (1 ... 3).contains(maximumValidations) else { throw IntegrationError.invalid("E supports <=6 on-demand automobile stops and <=3 validations") }
        services.resetRun()
        let forecasts = try await services.forecasts(points: draft.allPoints, draft: draft, progress: progress)
        let orders = LabFastPlanner.permutations(draft.stops)
        var candidates: [NativeTripCandidate] = []; var checked = Set<[String]>()
        var observations: [String: Double] = [:]; var ratios: [Double] = []
        var uncertain = true
        for attempt in 1 ... maximumValidations {
            try Task.checkCancellation()
            if attempt > 1 && !uncertain { break }
            var speculative = observations
            if !ratios.isEmpty {
                let ordered = ratios.sorted(); let scale = min(4, max(0.25, ordered[ordered.count / 2]))
                // Only the local shortlist uses this calibrated prior. Final provider cache is untouched.
                for a in draft.allPoints { for b in draft.allPoints where a.id != b.id {
                    let key = a.id + ">" + b.id
                    if speculative[key] == nil { speculative[key] = (300 + a.distance(to: b) / 8) * scale }
                }}
            }
            var estimates = orders.filter { !checked.contains($0.map(\.id)) }.map {
                LabFastPlanner.estimate($0, draft: draft, visitStart: services.integrationVisitStart,
                                        forecasts: forecasts, calibratedEdges: speculative)
            }.sorted(by: LabFastPlanner.ranked)
            // One deliberate alternative first stop tests an unobserved access edge.
            // Then return to calibrated best-first ranking. No assumption of symmetric costs.
            if attempt == 2, let first = candidates.first?.order.first {
                let diverse = estimates.filter { $0.order.first?.id != first }
                if !diverse.isEmpty { estimates = diverse }
            }
            guard let chosen = estimates.first else { break }
            checked.insert(chosen.order.map(\.id))
            services.event("routing.selective_surrogate", category: "optimizer", fields: [
                "policy": "E-v1-risk-25pct-15min-30min", "estimatedOnly": "true", "attempt": String(attempt),
                "limit": String(maximumValidations), "order": chosen.order.map(\.id).joined(separator: "/")])
            let value = try await NativeTripEngine.evaluate(chosen.order, draft: draft, services: services,
                                                            forecasts: forecasts, progress: progress)
            candidates.append(value)
            services.logs.recordJSON("routing.selective_validated_candidate", category: "optimizer", operationID: services.operationID, value: value)
            if value.legs.contains(where: { $0.chosen?.usable != true }) { break }
            for leg in value.legs {
                guard let seconds = leg.chosen?.seconds else { continue }
                let hour = draft.calendar.component(.hour, from: leg.departure)
                let peak = (7 ..< 10).contains(hour) || (16 ..< 19).contains(hour)
                let prior = (300 + leg.from.distance(to: leg.to) / 8) * (peak ? 1.35 : 1)
                ratios.append(seconds / prior)
                observations[leg.from.id + ">" + leg.to.id] = seconds
            }
            let best = candidates.min(by: NativeTripCandidate.better)!
            let mismatch = ratios.contains { $0 < 0.8 || $0 > 1.25 }
            let slack = best.finish.map { draft.deadline.timeIntervalSince($0) } ?? -.infinity
            uncertain = !best.feasible || mismatch || best.waitingMinutes >= 15 || slack < 1800
            services.event("routing.selective_decision", category: "optimizer", fields: [
                "continue": String(uncertain), "mismatch": String(mismatch), "bestFeasible": String(best.feasible),
                "waitingMinutes": String(best.waitingMinutes), "remainingSlackSeconds": String(slack)])
        }
        return .init(draft: draft, candidates: candidates, fastest: candidates.min(by: NativeTripCandidate.better),
                     weatherChoice: nil, forecasts: forecasts, requests: services.directionRequests,
                     weatherNote: "Weather informs speculative ranking; final legs use exact-departure provider calls.",
                     optimizerNote: "E experimental risk-triggered <=\(maximumValidations) validations; no optimality guarantee; observed edge calibration is speculative only.")
    }
}
