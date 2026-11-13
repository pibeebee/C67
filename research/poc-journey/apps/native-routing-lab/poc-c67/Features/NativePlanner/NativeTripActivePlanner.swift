import Foundation

@MainActor enum NativeTripActivePlanner {
    static func plan(
        _ projection: NativeTripReplanProjection, services: NativeTripAppleServices,
        progress: (String) -> Void
    ) async throws -> NativeTripReport {
        let draft = projection.draft
        try draft.validate(allowNoStops: true)
        if draft.stops.isEmpty {
            services.resetRun()
            let candidate = try await NativeTripEngine.evaluate(
                [], draft: draft, services: services,
                forecasts: [], progress: progress)
            return .init(
                draft: draft, candidates: [candidate], fastest: candidate.complete ? candidate : nil,
                forecasts: [], requests: services.directionRequests,
                weatherNote: "Ruas menuju titik akhir; data cuaca baru tidak diminta.",
                optimizerNote: "Tidak ada tujuan tersisa; endpoint asal tetap dipertahankan.")
        }
        return try await NativeTripTimeAwarePlanner.plan(
            draft, services: services,
            retainedOrder: projection.retainedOrder, progress: progress)
    }
}

/// Explicit local simulation only. It never supplies fallback values to live planning.
enum NativeTripActiveSimulation {
    static func seconds(from: String, to: String) -> Double {
        if from == to { return 0 }
        let edges = ["O>A": 600.0, "A>B": 600, "B>C": 600, "C>D": 600, "D>O": 1200]
        return edges["\(from)>\(to)"] ?? 3600
    }
    static func report() -> NativeTripReport {
        let date = ISO8601DateFormatter().date(from: "2026-11-05T01:00:00Z")!
        let origin = NativeTripPoint(
            id: "O", title: "Awal simulasi", query: "", latitude: 0, longitude: 0,
            resolvedName: "Sampel sintetis", selectionSource: "Simulasi lokal")
        let stops = ["A", "B", "C", "D"].enumerated().map { index, id in
            NativeTripStop(
                point: .init(
                    id: id, title: "Tujuan \(id) · simulasi", query: "",
                    latitude: 0, longitude: Double(index + 1) * 0.001, resolvedName: "Sampel sintetis",
                    selectionSource: "Simulasi lokal"))
        }
        var draft = NativeTripDraft(
            departure: date, timeZoneID: "Asia/Jakarta", origin: origin,
            end: origin, stops: stops, walking: false, transit: false, automobile: true,
            carUse: "onDemand")
        draft.finishBy = date.addingTimeInterval(4 * 3600)
        var candidate = NativeTripCandidate(id: "active-simulation", order: stops.map(\.id))
        var from = origin
        var cursor = date
        for (index, stop) in (stops + [.init(point: origin, role: .transfer)]).enumerated() {
            let seconds = Self.seconds(from: from.id, to: stop.id)
            let eta = NativeTripETA(
                id: "sim-\(index)", mode: .automobile, seconds: seconds,
                status: "available", note: "ETA sintetis; bukan data provider.")
            let arrival = cursor.addingTimeInterval(seconds)
            let dwell = stop.dwell(defaultMinutes: draft.defaultDwell)
            let leave = arrival.addingTimeInterval(Double(dwell) * 60)
            candidate.legs.append(
                .init(
                    id: "sim-leg-\(index)", from: from, to: stop.point,
                    departure: cursor, arrival: arrival, visit: arrival, leave: leave, dwellMinutes: dwell,
                    dwellSource: "simulasi", isReturn: index == stops.count, chosen: eta, options: [eta],
                    notes: []))
            candidate.travelMinutes += seconds / 60
            candidate.dwellMinutes += dwell
            from = stop.point
            cursor = leave
        }
        candidate.finish = cursor
        candidate.complete = true
        candidate.uncertainties = ["Lokasi, ETA dan jam simulasi; bukan bukti perjalanan nyata."]
        return .init(
            draft: draft, candidates: [candidate], fastest: candidate, forecasts: [], requests: 0,
            weatherNote: "Simulasi lokal tanpa prakiraan.",
            optimizerNote: "Simulasi replanning; tidak memakai provider live.", simulationKind: "active")
    }
}
