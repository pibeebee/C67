import Foundation

/// Test-only deterministic adapter. Production engines are compiled unchanged.
@MainActor final class NativeTripReplayLogs {
    var solvers: [[String: Any]] = []
    #if PIPELINE_CHECKS
        var refined: TripRoutingProblem?
    #endif
    func recordJSON<T: Encodable>(_ name: String, category: String, operationID: String, value: T) {
        #if PIPELINE_CHECKS
            if name == "routing.refined_snapshot", let data = try? JSONEncoder().encode(value) {
                refined = try? JSONDecoder().decode(TripRoutingProblem.self, from: data)
            }
        #endif
        guard name == "routing.solver_result",
              let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        solvers.append(
            object.filter {
                ["algorithm", "evaluations", "elapsed", "termination", "proof"].contains($0.key)
            })
    }
}

@MainActor final class NativeTripAppleServices {
    let logs = NativeTripReplayLogs()
    let operationID = "frozen-replay"
    private(set) var directionRequests = 0
    private(set) var cacheHits = 0
    var remainingETARequests: Int { max(0, limit - directionRequests) }
    var canRequestETA: Bool { remainingETARequests > 0 }
    private let limit: Int
    private let oracle: [String: [[String: Any]]]
    private let start: Date
    private var cache: [String: NativeTripETA] = [:]
    var requests: [[String: Any]] = []
    var events: [[String: Any]] = []

    init(_ input: [String: Any], draft: NativeTripDraft) {
        limit = min(1024, max(16, draft.routingRequestLimit ?? 96))
        start = draft.departure
        oracle = Dictionary(
            grouping: input["oracle"] as! [[String: Any]],
            by: {
                "\($0["from"] as! String)>\($0["to"] as! String):\($0["mode"] as! String)"
            })
    }
    func resetRun() {
        cache = [:]
        directionRequests = 0
        cacheHits = 0
        requests = []
        events = []
    }
    func event(
        _ name: String, category: String = "mapkit", level: String = "info",
        fields: [String: String] = [:]
    ) {
        events.append(["name": name, "fields": fields])
    }
    func forecasts(points: [NativeTripPoint], draft: NativeTripDraft, progress: (String) -> Void)
        async throws -> [NativeTripForecast]
    { [] }
    func options(
        from: NativeTripPoint, to: NativeTripPoint, departure: Date, draft: NativeTripDraft,
        retryUnavailable: Bool = false
    ) async throws -> [NativeTripETA] {
        var result: [NativeTripETA] = []
        for mode in draft.modes {
            try Task.checkCancellation()
            let key =
                "\(from.id)>\(to.id):\(mode.rawValue):\(mode == .walking ? 0 : departure.timeIntervalSince1970)"
            if retryUnavailable, mode != .transit, let saved = cache[key], !saved.usable,
               !["request_limit", "throttled"].contains(saved.status)
            {
                cache[key] = nil
            }
            var value = NativeTripETA(
                id: key, mode: mode, status: "unavailable", note: "Frozen replay oracle")
            if let saved = cache[key] {
                cacheHits += 1
                value = saved
                if mode == .walking, let seconds = value.seconds {
                    value.expectedDeparture = departure
                    value.expectedArrival = departure.addingTimeInterval(seconds)
                }
            } else if from.latitude == to.latitude && from.longitude == to.longitude {
                value.seconds = 0
                value.distance = 0
                value.status = "available"
                value.expectedDeparture = departure
                value.expectedArrival = departure
            } else if directionRequests >= limit {
                value.status = "request_limit"
            } else {
                directionRequests += 1
                let time = departure.timeIntervalSince(start)
                let arcKey = "\(from.id)>\(to.id):\(mode.rawValue)"
                if let arc = oracle[arcKey]?.first(where: {
                    ($0["start"] as? Double ?? 0) <= time && time < ($0["end"] as? Double ?? 172800)
                }) {
                    value.seconds = arc["seconds"] as? Double
                    value.status = arc["status"] as? String ?? "available"
                    value.expectedDeparture = departure
                    value.expectedArrival = value.seconds.map { departure.addingTimeInterval($0) }
                }
                cache[key] = value
                requests.append([
                    "from": from.id, "to": to.id, "mode": mode.rawValue, "departure": time,
                    "status": value.status, "seconds": value.seconds as Any? ?? NSNull(),
                ])
            }
            if mode == .walking, let seconds = value.seconds, value.usable,
               seconds > Double(draft.maximumWalkingMinutes * 60)
            {
                value.status = "excluded_by_walking_limit"
            }
            result.append(value)
        }
        return result
    }
}

#if !PIPELINE_CHECKS
    @main struct NativeTripPipelineReplay {
        @MainActor static func main() async throws {
            let args = CommandLine.arguments
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let input = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let draftData = try JSONSerialization.data(withJSONObject: input["draft"]!)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var draft = try decoder.decode(NativeTripDraft.self, from: draftData)
            if args[2] != "default" { draft.routingAlgorithm = args[2] }
            draft.routingSeed = Int(args[3])!
            let services = NativeTripAppleServices(input, draft: draft)
            let started = Date()
            var output: [String: Any] = [
                "case": input["id"]!, "algorithm": args[2], "seed": draft.routingSeed!,
            ]
            do {
                let report = try await NativeTripEngine.plan(draft, services: services, progress: { _ in })
                func candidate(_ c: NativeTripCandidate) -> [String: Any] {
                    [
                        "order": c.order, "complete": c.complete, "feasible": c.feasible,
                        "travel": c.travelMinutes * 60, "waiting": c.waitingMinutes * 60,
                        "dwell": c.dwellMinutes * 60,
                        "elapsed": c.finish.map { $0.timeIntervalSince(draft.departure) } as Any? ?? NSNull(),
                        "conflicts": c.conflicts,
                        "legs": c.legs.map { leg in
                            [
                                "from": leg.from.id, "to": leg.to.id,
                                "mode": leg.chosen?.mode.rawValue as Any? ?? NSNull(),
                                "seconds": leg.chosen?.seconds as Any? ?? NSNull(),
                                "departure": leg.departure.timeIntervalSince(draft.departure),
                                "arrival": leg.arrival.map { $0.timeIntervalSince(draft.departure) } as Any?
                                    ?? NSNull(),
                                "visit": leg.visit.map { $0.timeIntervalSince(draft.departure) } as Any?
                                    ?? NSNull(),
                                "leave": leg.leave.map { $0.timeIntervalSince(draft.departure) } as Any?
                                    ?? NSNull(),
                            ] as [String: Any]
                        },
                    ] as [String: Any]
                }
                output["selected"] = report.fastest.map(candidate) as Any? ?? NSNull()
                output["candidates"] = report.candidates.map(candidate)
                output["note"] = report.optimizerNote as Any? ?? NSNull()
            } catch { output["error"] = error.localizedDescription }
            output["wallSeconds"] = Date().timeIntervalSince(started)
            output["requests"] = services.directionRequests
            output["cacheHits"] = services.cacheHits
            output["requestTrace"] = services.requests
            output["events"] = services.events
            output["solvers"] = services.logs.solvers
            let encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            FileHandle.standardOutput.write(encoded)
            FileHandle.standardOutput.write(Data([10]))
        }
    }

#endif
