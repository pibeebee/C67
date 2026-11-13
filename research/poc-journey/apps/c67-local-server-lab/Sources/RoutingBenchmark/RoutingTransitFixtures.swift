import Foundation
import PlaceContextEngine
import TripIntegration

@MainActor public enum RoutingTransitFixtures {
    public static func feed(transfer: Bool) throws -> BuswayFeed {
        let original = try BuswayFeed.load()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        func pattern(id: String, route: String, category: String, from: String, to: String) -> [String: Any] {
            ["id": id, "routeID": route, "category": category, "serviceID": "benchmark", "headsign": "SYNTHETIC " + route, "directionID": "1", "shapeID": "synthetic-no-shape", "calls": [["stopID": from, "sequence": 1, "arrivalOffset": 0, "departureOffset": 0], ["stopID": to, "sequence": 2, "arrivalOffset": 600, "departureOffset": 600]], "frequencies": [["start": 0, "end": 86400, "headway": 600, "exactTimes": 0]]]
        }
        object["schemaVersion"] = 2; object["routeID"] = "network"; object["category"] = "TJ"
        object["services"] = [["id": "benchmark", "startDate": "20260101", "endDate": "20261231", "weekdays": Array(1 ... 7)]]
        object["patterns"] = transfer ? [pattern(id: "1-benchmark", route: "1", category: "BRT", from: "G00031", to: "G00021"), pattern(id: "6-benchmark", route: "6", category: "Angkutan Umum Integrasi", from: "G00021", to: "P00017")] : [pattern(id: "1-benchmark", route: "1", category: "BRT", from: "G00031", to: "P00017")]
        object["transfers"] = transfer ? [["fromStopID": "G00021", "toStopID": "G00021", "minimumSeconds": 120, "evidence": "SYNTHETIC interchange; not actual service"]] : []
        object["stops"] = (object["stops"] as! [[String: Any]]).filter { ["G00031", "G00021", "P00017"].contains($0["id"] as? String ?? "") }
        let feed = try JSONDecoder().decode(BuswayFeed.self, from: JSONSerialization.data(withJSONObject: object))
        try feed.validate(); return feed
    }
    public static func endpoints(_ feed: BuswayFeed) -> [String: RoutingEndpoint] {
        Dictionary(uniqueKeysWithValues: feed.stops.map { ($0.id, .init(id: $0.id, revision: "SYNTHETIC-platform", point: .init($0.latitude, $0.longitude))) })
    }
    public static func run() async throws -> [RoutingObservation] {
        var rows: [RoutingObservation] = []
        for transfer in [false, true] {
            let feed = try feed(transfer: transfer), now = feed.source.checkedAt.addingTimeInterval(1)
            let points = endpoints(feed)
            let base = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:])
            let memo = RoutingMemo(base: base)
            let adapter = try RoutingTransitAdapter(endpoints: points, feed: feed, walking: .init(provider: memo, provenance: "synthetic_walking"), now: now)
            for reverse in [false, true] {
                let clock = ContinuousClock.now, previous = base.calls
                let result = try await adapter.travel(from: reverse ? "P00017" : "G00031", to: reverse ? "G00031" : "P00017", departure: now)
                let expected = reverse ? result == nil : result?.details?.mode == "transjakarta"
                rows.append(.init(caseID: "tj-\(transfer ? "transfer-brt-nonbrt" : "direct")-\(reverse ? "reverse" : "forward")", backend: "shared_tj_synthetic_walking", policy: "fixed_leg", evidenceMode: "SYNTHETIC_SERVICE_ON_PUBLISHED_STOP_COORDINATES", outcome: expected ? "expected_match" : "defect", wallSeconds: RoutingFixtures.seconds(clock), calls: base.calls - previous, visited: 0, requiredRetained: expected, orderRetained: true, deadlineMet: true, arithmeticValid: result.map { abs($0.seconds - ($0.details?.walkingSeconds ?? 0) - ($0.details?.transitWaitingSeconds ?? 0) - (transfer ? 1200 : 600)) < 0.01 } ?? true, accessStatus: "platform_access_unverified", searchLimited: memo.calls >= 128))
            }
        }
        return rows
    }
    public static func itineraries() async throws -> [RoutingObservation] {
        let outbound = try feed(transfer: true)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(outbound)) as! [String: Any]
        let patterns = object["patterns"] as! [[String: Any]]
        object["patterns"] = patterns + patterns.map { value in
            var row = value; row["id"] = (row["id"] as! String) + "-return"; row["directionID"] = "0"
            var calls = row["calls"] as! [[String: Any]]
            let a = calls[0]["stopID"]!; calls[0]["stopID"] = calls[1]["stopID"]; calls[1]["stopID"] = a
            row["calls"] = calls; return row
        }
        let network = try JSONDecoder().decode(BuswayFeed.self, from: JSONSerialization.data(withJSONObject: object))
        let origin = outbound.stops.first { $0.id == "G00031" }!
        let far = outbound.stops.first { $0.id == "P00017" }!
        var points: [String: RoutingPoint] = ["origin": .init(origin.latitude, origin.longitude)]
        for index in 0 ..< 6 { points["synthetic-\(index)"] = .init(far.latitude + Double(index) * 0.00005, far.longitude) }
        let selections: [(String, [String])] = [
            ("n1", ["synthetic-0"]), ("n3", ["synthetic-0", "synthetic-1", "synthetic-2"]),
            ("n6", (0 ..< 6).map { "synthetic-\($0)" }),
            ("replace_first", ["synthetic-3", "synthetic-1", "synthetic-2"]),
            ("replace_middle", ["synthetic-0", "synthetic-3", "synthetic-2"]),
            ("replace_last", ["synthetic-0", "synthetic-1", "synthetic-3"]),
            ("reorder", ["synthetic-2", "synthetic-0", "synthetic-1"]),
            ("delete", ["synthetic-0", "synthetic-2"]),
            ("add", ["synthetic-0", "synthetic-1", "synthetic-2", "synthetic-3"])
        ]
        var rows: [RoutingObservation] = []
        for (operation, ids) in selections {
            for policy in ["baseline", "finalists"] {
                let input = try RoutingFixtures.request(ids: ids, fixed: operation.hasPrefix("n") == false)
                let endpoints = Dictionary(uniqueKeysWithValues: (["origin"] + ids).map { ($0, RoutingEndpoint(id: $0, revision: "synthetic-tj-edit", point: points[$0])) })
                let base = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:])
                let adapter = try RoutingTransitAdapter(endpoints: endpoints, feed: network, walking: .init(provider: base, provenance: "synthetic_walking"), now: RoutingFixtures.now)
                let clock = ContinuousClock.now, required = Set(ids)
                let result: ContextItineraryResult
                if policy == "baseline" { result = try await OptionalItineraryPlanner.plan(input, requiredIDs: required, provider: adapter, now: RoutingFixtures.now) }
                else { result = try await FinalistRoutingPlanner.plan(input, required: required, provider: adapter, points: points, now: RoutingFixtures.now) }
                var row = RoutingFixtures.observation(id: "tj-itinerary-" + operation, backend: "shared_tj_synthetic_walking", policy: policy, mode: "SYNTHETIC_SERVICE_ON_PUBLISHED_STOP_COORDINATES", seconds: RoutingFixtures.seconds(clock), result: result, required: required, input: input)
                row.calls = base.calls
                rows.append(row)
            }
        }
        return rows
    }
}
