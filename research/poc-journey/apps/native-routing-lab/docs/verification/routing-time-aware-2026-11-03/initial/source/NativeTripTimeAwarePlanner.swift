import Foundation

/// Bounded hybrid pipeline. Every returned candidate has been evaluated with per-leg ETA.
@MainActor enum NativeTripTimeAwarePlanner {
    static func plan(
        _ draft: NativeTripDraft, services: NativeTripAppleServices, progress: (String) -> Void
    ) async throws -> NativeTripReport {
        try draft.validate()
        if draft.selectedRoutingAlgorithm == .exact && draft.stops.count > 8 {
            throw NativeTripError.message("Enumerasi mendukung maksimal 8 tujuan. Pilih algoritme lain.")
        }
        services.resetRun()
        let forecasts = try await services.forecasts(points: draft.allPoints, draft: draft, progress: progress)
        let upperBound = (draft.stops.count + 1) * draft.modes.count
        var candidates: [NativeTripCandidate] = []
        let started = Date()
        // Validate a real fallback before acquiring a matrix. Do not let snapshot cost consume
        // the request budget needed to produce at least one complete live candidate.
        for order in NativeTripEngine.orders(draft) {
            guard candidates.isEmpty || services.remainingETARequests >= upperBound else { break }
            let candidate = try await NativeTripEngine.evaluate(
                order, draft: draft, services: services, forecasts: forecasts, progress: progress)
            candidates.append(candidate)
            record(candidate, source: "baseline_live", draft: draft, services: services)
        }
        let baseline = candidates.filter(\.complete).min(by: NativeTripCandidate.better)
        var note = "Baseline live dipertahankan; anggaran belum cukup untuk pencarian tambahan."
        if services.remainingETARequests >= upperBound + draft.modes.count {
            var problem = try await NativeTripRoutingBridge.snapshot(
                draft, services: services, forecasts: forecasts, reserve: upperBound, progress: progress)
            let byID = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
            for candidate in candidates { incorporate(candidate, draft: draft, into: &problem) }
            var usedEvaluations = 0
            var usedCPU = 0.0
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
                    "routing.solver_result", category: "optimizer", operationID: services.operationID, value: result)
                let checked = Set(candidates.map { $0.order.joined(separator: "/") })
                let proposals = finalists(result.alternatives).filter {
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
            note = "\(draft.selectedRoutingAlgorithm.title) · elapsed_v2 · \(usedEvaluations) evaluasi · \(rounds) putaran · \(validationCount) kandidat tambahan live. Baseline live tetap ikut pemilihan. Snapshot dan sampel waktu terbatas tidak membuktikan optimum lalu lintas dunia nyata."
            services.logs.recordJSON(
                "routing.refined_snapshot", category: "optimizer", operationID: services.operationID, value: problem)
        }
        let complete = candidates.filter(\.complete).sorted(by: NativeTripCandidate.better)
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
                "carUse": draft.carUse ?? "privateCar",
            ])
        return .init(
            draft: draft, candidates: candidates, fastest: best, weatherChoice: weather,
            forecasts: forecasts, requests: services.directionRequests,
            weatherNote: weather == nil
                ? "Alternatif cuaca ditunda sampai data paparan cukup; jam buka dan batas selesai tetap diperiksa."
                : "Alternatif cuaca berada dalam batas tambahan total durasi trip.", optimizerNote: note)
    }

    private static func finalists(_ pool: [TripRoutingEvaluation]) -> [TripRoutingEvaluation] {
        var result = Array(pool.sorted(by: TripRoutingEvaluator.better).prefix(3))
        if let travel = pool.filter({ $0.feasible && $0.fullTour }).min(by: { $0.travel < $1.travel }),
           !result.contains(where: { $0.order == travel.order }) { result.append(travel) }
        if let wait = pool.filter({ $0.feasible && $0.fullTour }).min(by: { $0.waiting < $1.waiting }),
           !result.contains(where: { $0.order == wait.order }) { result.append(wait) }
        return result
    }

    private static func incorporate(
        _ candidate: NativeTripCandidate, draft: NativeTripDraft, into problem: inout TripRoutingProblem
    ) {
        let ids = Dictionary(uniqueKeysWithValues: problem.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let order = candidate.order.compactMap { ids[$0] }
        if candidate.complete, order.count == problem.targets.count,
           !problem.baselineOrders.contains(order) { problem.baselineOrders.insert(order, at: 0) }
        for leg in candidate.legs {
            guard let from = ids[leg.from.id], let to = ids[leg.to.id], from != to else { continue }
            let t = max(0, leg.departure.timeIntervalSince(draft.departure))
            for option in leg.options {
                let start = option.mode == .walking ? 0 : t
                let end = option.mode == .walking ? 172800 : t + 0.001
                var keep: [TripRoutingArc] = []
                for arc in problem.arcs {
                    guard arc.from == from, arc.to == to, arc.mode == option.mode.rawValue,
                          arc.start < end, start < arc.end else { keep.append(arc); continue }
                    if arc.start < start { var left = arc; left.end = start; keep.append(left) }
                    if arc.end > end { var right = arc; right.start = end; keep.append(right) }
                }
                keep.append(.init(from: from, to: to, mode: option.mode.rawValue, seconds: option.seconds,
                                  start: start, end: end, status: option.status, note: "Observed per-leg ETA; no all-day extrapolation."))
                problem.arcs = keep
            }
        }
        problem.kind = "snapshot_with_observed_departures"
    }

    private static func record(
        _ candidate: NativeTripCandidate, source: String, draft: NativeTripDraft, services: NativeTripAppleServices
    ) {
        services.event("routing.live_candidate", category: "optimizer", fields: [
            "source": source, "order": candidate.order.joined(separator: " → "),
            "complete": String(candidate.complete), "feasible": String(candidate.feasible),
            "elapsedMinutes": String(candidate.elapsedMinutes), "travelMinutes": String(candidate.travelMinutes),
            "waitingMinutes": String(candidate.waitingMinutes), "conflicts": candidate.conflicts.joined(separator: " | ")
        ])
    }
}
