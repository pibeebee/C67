import Foundation

/// Bounded adaptive hybrid. Only provider-validated candidates can become the result.
@MainActor enum NativeTripTimeAwarePlanner {
    struct Decision {
        var optimize: Bool
        var reason: String
        var estimatedSavingMinutes = 0.0
        var evaluations = 0
    }

    // Experimental policy constants, not calibrated probabilities or provider guarantees.
    static let largeWaitMinutes = 20.0
    static let minimumSavingMinutes = 5.0
    static let minimumSavingFraction = 0.03

    /// Cheap screening only. Observed costs and distance-calibrated estimates must never
    /// enter the ETA cache, routing snapshot or returned itinerary as provider evidence.
    static func decision(
        _ draft: NativeTripDraft, candidates: [NativeTripCandidate],
        forecasts: [NativeTripForecast]
    ) throws -> Decision {
        try Task.checkCancellation()
        guard draft.selectedRoutingAlgorithm == .hybrid, draft.routingAdaptive != false else {
            return .init(optimize: true, reason: "full_search_requested")
        }
        guard let best = candidates.min(by: NativeTripCandidate.better), best.feasible else {
            return .init(optimize: true, reason: "baseline_infeasible_or_incomplete")
        }
        // With one or two destinations the validated geographic seeds cover every order.
        let expectedOrders = draft.stops.count == 1 ? 1 : 2
        if draft.stops.count <= 2,
           Set(candidates.filter(\.complete).map(\.order)).count == expectedOrders
        {
            return .init(optimize: false, reason: "all_small_orders_validated")
        }
        if best.waitingMinutes >= largeWaitMinutes {
            return .init(optimize: true, reason: "large_baseline_wait")
        }
        if draft.usesPrivateCar {
            return .init(optimize: true, reason: "private_car_strategy_uncertainty")
        }
        if draft.rainWeight > 0, forecasts.contains(where: { !$0.hours.isEmpty }) {
            return .init(optimize: true, reason: "weather_alternatives")
        }
        let stops = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
        for leg in best.legs where !leg.isReturn {
            if let closes = stops[leg.to.id]?.opening?.closesMinute, let leave = leg.leave,
               draft.clockDate(minutes: closes).timeIntervalSince(leave) < 15 * 60
            {
                return .init(optimize: true, reason: "tight_closing_margin")
            }
        }
        // An absence of geometric improvement is weak evidence when unseen road costs
        // dominate. Only screen for early acceptance when the final visit is held at an
        // opening time: earlier upstream travel can then be absorbed by existing waiting.
        // This is still a heuristic, not a time-dependent shortest-path certificate.
        guard let lastVisit = best.legs.last(where: { !$0.isReturn }),
              let arrival = lastVisit.arrival, let visit = lastVisit.visit,
              visit.timeIntervalSince(arrival) >= 60,
              stops[lastVisit.to.id]?.opening?.opensMinute != nil
        else {
            return .init(optimize: true, reason: "unobserved_shortcut_uncertainty")
        }
        let points = Dictionary(uniqueKeysWithValues: draft.allPoints.map { ($0.id, $0) })
        var observed: [String: Double] = [:]
        var ratios: [Double] = []
        for candidate in candidates {
            for leg in candidate.legs {
                guard let seconds = leg.chosen?.seconds else { continue }
                let key = "\(leg.from.id)/\(leg.to.id)"
                observed[key] = min(observed[key] ?? .infinity, seconds)
            }
        }
        for candidate in candidates {
            for leg in candidate.legs {
                let distance = leg.from.distance(to: leg.to)
                if distance > 50, let seconds = leg.chosen?.seconds, seconds > 0 {
                    ratios.append(seconds / distance)
                }
            }
        }
        guard ratios.count >= 3 else {
            return .init(optimize: true, reason: "insufficient_screening_data")
        }
        ratios.sort()
        let secondsPerMeter = ratios[ratios.count / 2]
        let limit = min(512, draft.routingConfiguration.evaluationLimit / 10)
        let screeningStarted = Date()
        let secondsLimit = min(0.05, draft.routingConfiguration.secondsLimit / 10)
        var evaluations = 0
        func estimate(_ order: [String]) -> Double? {
            guard evaluations < limit, Date().timeIntervalSince(screeningStarted) < secondsLimit else {
                return nil
            }
            evaluations += 1
            var cursor = draft.departure
            var from = draft.origin.id
            for to in order + [draft.endPoint.id] {
                guard let a = points[from], let b = points[to] else { return nil }
                cursor.addTimeInterval(observed["\(from)/\(to)"] ?? a.distance(to: b) * secondsPerMeter)
                if let stop = stops[to], to != draft.endPoint.id {
                    if let opens = stop.opening?.opensMinute, stop.role == .visit {
                        cursor = max(cursor, draft.clockDate(minutes: opens))
                    }
                    cursor.addTimeInterval(Double(stop.dwell(defaultMinutes: draft.defaultDwell)) * 60)
                    if let closes = stop.opening?.closesMinute, stop.role == .visit,
                       cursor > draft.clockDate(minutes: closes)
                    {
                        return .infinity
                    }
                }
                from = to
            }
            return cursor > draft.deadline ? .infinity : cursor.timeIntervalSince(draft.departure) / 60
        }
        let seeds = candidates.filter(\.complete).map(\.order)
        let base = seeds.compactMap { estimate($0) }.min() ?? .infinity
        guard base.isFinite,
              abs(base - best.elapsedMinutes) <= max(minimumSavingMinutes, best.elapsedMinutes * 0.05)
        else {
            return .init(optimize: true, reason: "screening_model_mismatch", evaluations: evaluations)
        }
        let threshold = max(minimumSavingMinutes, best.elapsedMinutes * minimumSavingFraction)
        var saving = 0.0
        var checked = Set(seeds)
        for seed in seeds {
            for i in seed.indices {
                try Task.checkCancellation()
                for j in seed.indices where i != j {
                    var alternatives: [[String]] = []
                    var relocated = seed
                    let item = relocated.remove(at: i)
                    relocated.insert(item, at: j)
                    alternatives.append(relocated)
                    var swapped = seed
                    swapped.swapAt(i, j)
                    alternatives.append(swapped)
                    for order in alternatives where checked.insert(order).inserted {
                        guard let elapsed = estimate(order) else {
                            return .init(
                                optimize: true, reason: "screening_budget_exhausted",
                                estimatedSavingMinutes: saving, evaluations: evaluations)
                        }
                        saving = max(saving, base - elapsed)
                        if saving >= threshold {
                            return .init(
                                optimize: true, reason: "estimated_material_gain",
                                estimatedSavingMinutes: saving, evaluations: evaluations)
                        }
                    }
                }
            }
        }
        return .init(
            optimize: false, reason: "no_material_estimated_gain",
            estimatedSavingMinutes: saving, evaluations: evaluations)
    }

    static func plan(
        _ draft: NativeTripDraft, services: NativeTripAppleServices, retainedOrder: [String]? = nil,
        progress: (String) -> Void
    ) async throws -> NativeTripReport {
        try draft.validate()
        if draft.selectedRoutingAlgorithm == .exact && draft.stops.count > 8 {
            throw NativeTripError.message("Enumerasi mendukung maksimal 8 tujuan. Pilih algoritme lain.")
        }
        services.resetRun()
        let forecasts = try await services.forecasts(
            points: draft.allPoints, draft: draft, progress: progress)
        let upperBound = (draft.stops.count + 1) * draft.modes.count
        var candidates: [NativeTripCandidate] = []
        let started = Date()
        // Validate a real fallback before acquiring a matrix. Do not let snapshot cost consume
        // the request budget needed to produce at least one complete live candidate.
        var orders = NativeTripEngine.orders(draft)
        if let retainedOrder {
            let byID = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
            guard retainedOrder.count == draft.stops.count, Set(retainedOrder) == Set(byID.keys) else {
                throw NativeTripError.message("Urutan sisa tidak cocok dengan tujuan yang masih wajib.")
            }
            orders.removeAll { $0.map(\.id) == retainedOrder }
            orders.insert(retainedOrder.map { byID[$0]! }, at: 0)
        }
        func ranked(_ a: NativeTripCandidate, _ b: NativeTripCandidate) -> Bool {
            if a.complete == b.complete, a.feasible == b.feasible, a.conflicts.count == b.conflicts.count,
               a.elapsedMinutes == b.elapsedMinutes, a.travelMinutes == b.travelMinutes,
               let retainedOrder, a.order != b.order
            {
                if a.order == retainedOrder { return true }
                if b.order == retainedOrder { return false }
            }
            return NativeTripCandidate.better(a, b)
        }
        for order in orders {
            guard candidates.isEmpty || services.remainingETARequests >= upperBound else { break }
            let candidate = try await NativeTripEngine.evaluate(
                order, draft: draft, services: services, forecasts: forecasts, progress: progress)
            candidates.append(candidate)
            record(candidate, source: "baseline_live", draft: draft, services: services)
        }
        let baseline = candidates.filter(\.complete).min(by: ranked)
        let screeningStarted = Date()
        let screening = try decision(draft, candidates: candidates, forecasts: forecasts)
        let screeningSeconds = Date().timeIntervalSince(screeningStarted)
        services.event(
            "routing.adaptive_decision", category: "optimizer",
            fields: [
                "optimize": String(screening.optimize), "reason": screening.reason,
                "estimatedSavingMinutes": String(screening.estimatedSavingMinutes),
                "screeningEvaluations": String(screening.evaluations),
                "screeningSeconds": String(screeningSeconds),
                "baselineRequests": String(services.directionRequests),
                "largeWaitMinutes": String(largeWaitMinutes),
                "minimumSavingMinutes": String(minimumSavingMinutes),
                "minimumSavingFraction": String(minimumSavingFraction),
            ])
        var note = "Baseline live dipertahankan; anggaran belum cukup untuk pencarian tambahan."
        if !screening.optimize {
            let explanation =
                screening.reason == "all_small_orders_validated"
                    ? "Seluruh urutan kunjungan sudah divalidasi."
                    : "Pemeriksaan awal belum menemukan penghematan waktu yang berarti."
            note =
                "Hybrid adaptif · baseline tervalidasi dipertahankan. \(explanation) Tidak ada request optimasi tambahan; hasil belum terbukti optimum."
            progress("Baseline tervalidasi dipertahankan; optimasi tambahan dilewati")
        } else if services.remainingETARequests >= upperBound + draft.modes.count {
            var problem = try await NativeTripRoutingBridge.snapshot(
                draft, services: services, forecasts: forecasts, reserve: upperBound, progress: progress)
            let byID = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
            for candidate in candidates { incorporate(candidate, draft: draft, into: &problem) }
            var usedEvaluations = screening.evaluations
            var usedCPU = screeningSeconds
            var rounds = 0
            var validationCount = 0
            while rounds < 4 {
                try Task.checkCancellation()
                var config = draft.routingConfiguration
                guard usedEvaluations < config.evaluationLimit, usedCPU < config.secondsLimit else { break }
                config.evaluationLimit -= usedEvaluations
                config.secondsLimit -= usedCPU
                progress("Menyusun urutan berdasarkan durasi trip · putaran \(rounds + 1)")
                let result = try await TripRoutingWorker().solve(
                    draft.selectedRoutingAlgorithm, problem: problem, configuration: config)
                usedEvaluations += result.evaluations
                usedCPU += result.elapsed
                rounds += 1
                services.logs.recordJSON(
                    "routing.solver_result", category: "optimizer", operationID: services.operationID,
                    value: result)
                let checked = Set(candidates.map { $0.order.joined(separator: "/") })
                let proposals = finalists(result.alternatives, problem: problem).filter {
                    !checked.contains($0.order.map { problem.nodes[$0].id }.joined(separator: "/"))
                }
                guard services.remainingETARequests >= upperBound,
                      let proposal = proposals.first(where: { $0.complete && $0.fullTour })
                else { break }
                let order = proposal.order.compactMap { byID[problem.nodes[$0].id] }
                guard order.count == draft.stops.count else { break }
                progress("Memvalidasi kandidat tambahan sesuai jam setiap ruas")
                let candidate = try await NativeTripEngine.evaluate(
                    order, draft: draft, services: services, forecasts: forecasts, progress: progress)
                candidates.append(candidate)
                validationCount += 1
                record(candidate, source: "selective_live", draft: draft, services: services)
                // Replace only the observed departure instant, never extrapolate a measured ETA
                // across the entire day. Unsampled times retain the explicitly approximate snapshot.
                incorporate(candidate, draft: draft, into: &problem)
            }
            note =
                "\(draft.selectedRoutingAlgorithm.title) · elapsed_v2 · \(usedEvaluations) evaluasi · \(rounds) putaran · \(validationCount) kandidat tambahan live. Baseline live tetap ikut pemilihan. Snapshot dan sampel waktu terbatas tidak membuktikan optimum lalu lintas dunia nyata."
            services.logs.recordJSON(
                "routing.refined_snapshot", category: "optimizer", operationID: services.operationID,
                value: problem)
        }
        let complete = candidates.filter(\.complete).sorted(by: ranked)
        let best = complete.first
        let weather = complete.filter {
            guard let best, best.feasible else { return false }
            return $0.feasible && $0.unknownWeatherMinutes < 0.000001
                && $0.elapsedMinutes <= best.elapsedMinutes + Double(draft.extraWeatherMinutes)
        }.min {
            $0.elapsedMinutes + $0.rainExposureMinutes * draft.rainWeight
                < $1.elapsedMinutes + $1.rainExposureMinutes * draft.rainWeight
        }
        services.event(
            "routing.pipeline_completed", category: "optimizer",
            fields: [
                "objective": "elapsed_v2", "candidateCount": String(candidates.count),
                "baselineElapsedMinutes": baseline.map { String($0.elapsedMinutes) } ?? "unknown",
                "selectedElapsedMinutes": best.map { String($0.elapsedMinutes) } ?? "unknown",
                "requests": String(services.directionRequests),
                "elapsedSeconds": String(Date().timeIntervalSince(started)),
                "carUse": draft.automobile == true ? (draft.carUse ?? "privateCar") : "disabled",
            ])
        return .init(
            draft: draft, candidates: candidates, fastest: best, weatherChoice: weather,
            forecasts: forecasts, requests: services.directionRequests,
            weatherNote: weather == nil
                ? "Alternatif cuaca ditunda sampai data paparan cukup; jam buka dan batas selesai tetap diperiksa."
                : "Alternatif cuaca berada dalam batas tambahan total durasi trip.", optimizerNote: note)
    }

    private static func finalists(
        _ pool: [TripRoutingEvaluation], problem: TripRoutingProblem
    ) -> [TripRoutingEvaluation] {
        let ranked = pool.sorted(by: TripRoutingEvaluator.better)
        var result = Array(ranked.prefix(1))
        if let weather = TripRoutingEvaluator(problem).weatherChoice(pool),
           !result.contains(where: { $0.order == weather.order })
        {
            result.append(weather)
        }
        if let travel = pool.filter({ $0.feasible && $0.fullTour }).min(by: { $0.travel < $1.travel }),
           !result.contains(where: { $0.order == travel.order })
        {
            result.append(travel)
        }
        if let wait = pool.filter({ $0.feasible && $0.fullTour }).min(by: { $0.waiting < $1.waiting }),
           !result.contains(where: { $0.order == wait.order })
        {
            result.append(wait)
        }
        for candidate in ranked.prefix(3) where !result.contains(where: { $0.order == candidate.order })
        {
            result.append(candidate)
        }
        return result
    }

    private static func incorporate(
        _ candidate: NativeTripCandidate, draft: NativeTripDraft, into problem: inout TripRoutingProblem
    ) {
        let ids = Dictionary(
            uniqueKeysWithValues: problem.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let order = candidate.order.compactMap { ids[$0] }
        if candidate.complete, order.count == problem.targets.count,
           !problem.baselineOrders.contains(order)
        {
            problem.baselineOrders.insert(order, at: 0)
        }
        for leg in candidate.legs {
            guard let from = ids[leg.from.id], let to = ids[leg.to.id], from != to else { continue }
            let t = max(0, leg.departure.timeIntervalSince(draft.departure))
            for option in leg.options {
                let start = option.mode == .walking ? 0 : t
                let end = option.mode == .walking ? 172800 : t + 0.001
                var keep: [TripRoutingArc] = []
                for arc in problem.arcs {
                    guard arc.from == from, arc.to == to, arc.mode == option.mode.rawValue,
                          arc.start < end, start < arc.end
                    else {
                        keep.append(arc)
                        continue
                    }
                    if arc.start < start {
                        var left = arc
                        left.end = start
                        keep.append(left)
                    }
                    if arc.end > end {
                        var right = arc
                        right.start = end
                        keep.append(right)
                    }
                }
                keep.append(
                    .init(
                        from: from, to: to, mode: option.mode.rawValue, seconds: option.seconds,
                        start: start, end: end, status: option.status,
                        note: "Observed per-leg ETA; no all-day extrapolation."))
                problem.arcs = keep
            }
        }
        problem.kind = "snapshot_with_observed_departures"
    }

    private static func record(
        _ candidate: NativeTripCandidate, source: String, draft: NativeTripDraft,
        services: NativeTripAppleServices
    ) {
        services.event(
            "routing.live_candidate", category: "optimizer",
            fields: [
                "source": source, "order": candidate.order.joined(separator: " → "),
                "complete": String(candidate.complete), "feasible": String(candidate.feasible),
                "elapsedMinutes": String(candidate.elapsedMinutes),
                "travelMinutes": String(candidate.travelMinutes),
                "waitingMinutes": String(candidate.waitingMinutes),
                "conflicts": candidate.conflicts.joined(separator: " | "),
            ])
    }
}
