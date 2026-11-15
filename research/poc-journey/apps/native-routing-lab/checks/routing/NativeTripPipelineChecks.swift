import Foundation

@main struct NativeTripPipelineChecks {
    @MainActor static func main() async throws {
        let origin = NativeTripPoint(
            id: "origin", title: "Start", query: "", latitude: -6.2, longitude: 106.8)
        let points = (1 ... 4).map {
            NativeTripPoint(
                id: "p\($0)", title: "Place \($0)", query: "", latitude: -6.2 + Double($0) * 0.005,
                longitude: 106.8 + Double($0 % 2) * 0.008)
        }
        var draft = NativeTripDraft(
            departure: ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z")!,
            timeZoneID: "Asia/Jakarta", origin: origin, end: origin,
            stops: points.map { NativeTripStop(point: $0, role: .visit) })
        draft.walking = false
        draft.transit = false
        draft.automobile = true
        draft.carUse = "onDemand"
        draft.routingEvaluationLimit = 4000
        draft.routingSecondsLimit = 2
        draft.stops[0].opening = .init(opensMinute: 600)
        var arcs: [[String: Any]] = []
        for a in [origin] + points {
            for b in [origin] + points where a.id != b.id {
                arcs.append([
                    "from": a.id, "to": b.id, "mode": "automobile", "seconds": 600.0, "status": "available",
                ])
            }
        }
        let services = NativeTripAppleServices(["oracle": arcs], draft: draft)
        let report = try await NativeTripEngine.plan(draft, services: services, progress: { _ in })
        precondition(draft.selectedRoutingAlgorithm == .hybrid && report.fastest?.feasible == true)
        let baseline = report.candidates.prefix(NativeTripEngine.orders(draft).count).filter(\.feasible)
        precondition(report.fastest!.elapsedMinutes <= baseline.map(\.elapsedMinutes).min()!)
        precondition(report.requests <= 96 && report.requests == services.requests.count)
        print("PASS 1: default hybrid retains validated baseline and obeys shared provider cap")
        let refined = services.logs.refined!
        try refined.validate()
        let observations = refined.arcs.filter { $0.note?.contains("Observed per-leg") == true }
        precondition(!observations.isEmpty && observations.contains { $0.start > 0 })
        precondition(observations.allSatisfy { $0.end - $0.start <= 0.001001 })
        for observed in observations {
            precondition(
                !refined.arcs.contains {
                    $0.from == observed.from && $0.to == observed.to && $0.mode == observed.mode
                        && $0.start < observed.end && observed.start < $0.end
                        && ($0.start != observed.start || $0.end != observed.end)
                })
        }
        print(
            "PASS 2: observed departure samples split intervals without all-day extrapolation or overlap")

        draft.routingRequestLimit = 16
        let limited = NativeTripAppleServices(["oracle": arcs], draft: draft)
        let limitedReport = try await NativeTripEngine.plan(
            draft, services: limited, progress: { _ in })
        precondition(limitedReport.fastest?.complete == true && limited.directionRequests <= 16)
        print(
            "PASS 3: low-budget planning keeps a complete fallback instead of consuming all requests on a matrix"
        )

        let unavailable = arcs.map { arc -> [String: Any] in
            var value = arc
            value.removeValue(forKey: "seconds")
            value["status"] = "directions_not_available"
            return value
        }
        let missing = NativeTripAppleServices(["oracle": unavailable], draft: draft)
        let missingReport = try await NativeTripEngine.plan(
            draft, services: missing, progress: { _ in })
        precondition(
            missingReport.fastest == nil && missingReport.candidates.allSatisfy { !$0.complete })
        precondition(missing.directionRequests <= 16)
        print(
            "PASS 4: missing provider data never becomes a zero-duration route or a fabricated complete trip"
        )

        draft.stops = Array(draft.stops.prefix(2))
        draft.stops[0].opening = nil
        draft.walking = true
        draft.routingRequestLimit = 96
        var mixed: [[String: Any]] = []
        for a in [origin] + Array(points.prefix(2)) {
            for b in [origin] + Array(points.prefix(2)) where a.id != b.id {
                mixed.append([
                    "from": a.id, "to": b.id, "mode": "walking",
                    "seconds": a.id == "p1" && b.id == "p2" ? 1.0 : 100.0, "status": "available",
                ])
                mixed.append([
                    "from": a.id, "to": b.id, "mode": "automobile",
                    "seconds": (a.id == "origin" && b.id == "p1") || (a.id == "p2" && b.id == "origin")
                        ? 1.0 : 100.0, "status": "available",
                ])
            }
        }
        var provider = NativeTripAppleServices(["oracle": mixed], draft: draft)
        let taxi = try await NativeTripEngine.evaluate(
            draft.stops, draft: draft, services: provider, forecasts: [], progress: { _ in })
        precondition(abs(taxi.travelMinutes * 60 - 3) < 0.001)
        draft.carUse = nil
        precondition(draft.usesPrivateCar)
        provider = NativeTripAppleServices(["oracle": mixed], draft: draft)
        let car = try await NativeTripEngine.evaluate(
            draft.stops, draft: draft, services: provider, forecasts: [], progress: { _ in })
        precondition(
            abs(car.travelMinutes * 60 - 102) < 0.001
                && car.legs.allSatisfy { $0.chosen?.mode == .automobile })
        draft.carUse = "unknown-policy"
        do {
            try draft.validate()
            preconditionFailure("Invalid car use accepted")
        } catch {}
        draft.carUse = "onDemand"
        print(
            "PASS 5: live private-car policy matches model; legacy automobile drafts use conservative policy"
        )

        let cancelled = Task { @MainActor in
            try await NativeTripEngine.plan(
                draft, services: NativeTripAppleServices(["oracle": mixed], draft: draft),
                progress: { _ in })
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancellation swallowed")
        } catch is CancellationError {}
        print("PASS 6: cancellation exits the full planning pipeline")
        print(
            "6 full-pipeline checks passed on macOS with deterministic adapter; no network or iPhone validation."
        )
    }
}
