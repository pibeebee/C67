import Foundation
import XCTest

@testable import C67RoutingHarness

struct JakartaFixture: Decodable {
    static let monas = "0CE4F07E-E3A7-467F-A0F1-D4C715AC6FBE"
    static let grandIndonesia = "E32284F7-2A9E-4739-9991-4A086BB990DF"
    static let kelapaGading = "106E65CA-64AA-4292-9D96-DED708AF9D94"
    static let kotaTua = "BF2C3EFA-9309-4E4D-A550-2DE23C235AFC"
    static let earlyOrder = [grandIndonesia, monas, kotaTua, kelapaGading]
    static let lateOrder = Array(earlyOrder.reversed())

    struct Arc: Codable {
        var from: String
        var to: String
        var mode: String
        var seconds: Double?
        var start: Double
        var end: Double
        var status: String
    }
    var id: String
    var draft: NativeTripDraft
    var oracle: [Arc]
    var provenance: String
    var source: String
    var sourceSHA256: String

    static func load(_ name: String = "jakarta-recorded-static") throws -> Self {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    mutating func keep(_ ids: [String]) {
        let byID = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
        draft.stops = ids.map { byID[$0]! }
    }

    @MainActor func services() throws -> NativeTripAppleServices {
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oracle))
        return NativeTripAppleServices(["oracle": value], draft: draft)
    }

    @MainActor func problem() -> TripRoutingProblem {
        let points = draft.allPoints
        let index = Dictionary(
            uniqueKeysWithValues: points.enumerated().map { ($0.element.id, $0.offset) })
        let stops = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
        let nodes = points.map { p in
            let stop = stops[p.id]
            return TripRoutingNode(
                id: p.id, name: p.title, x: p.longitude!, y: p.latitude!,
                dwell: Double(stop?.dwell(defaultMinutes: draft.defaultDwell) ?? 0) * 60,
                opens: stop?.opening?.opensMinute.map {
                    draft.clockDate(minutes: $0).timeIntervalSince(draft.departure)
                },
                closes: stop?.opening?.closesMinute.map {
                    draft.clockDate(minutes: $0).timeIntervalSince(draft.departure)
                },
                exposure: stop?.exposure.factor)
        }
        let arcs = oracle.compactMap { a -> TripRoutingArc? in
            guard let from = index[a.from], let to = index[a.to] else { return nil }
            return .init(
                from: from, to: to, mode: a.mode, seconds: a.seconds, start: a.start, end: a.end,
                status: a.status)
        }
        return .init(
            label: "Jakarta recorded ETA unit fixture", kind: "recorded_static_test", nodes: nodes,
            targets: draft.stops.map { index[$0.id]! }, origin: index[draft.origin.id]!,
            end: index[draft.endPoint.id]!,
            deadline: draft.endOfDay.timeIntervalSince(draft.departure), arcs: arcs,
            baselineOrders: NativeTripEngine.orders(draft).map { $0.map { index[$0.id]! } },
            privateCar: draft.usesPrivateCar)
    }

    func indices(_ ids: [String], in problem: TripRoutingProblem) -> [Int] {
        ids.map { id in problem.nodes.firstIndex { $0.id == id }! }
    }

    @MainActor func record(
        _ candidate: NativeTripCandidate, scenario: String, requests: Int, wallSeconds: Double,
        source: String = "recorded_static", extra: [String: Any] = [:]
    ) throws {
        var value: [String: Any] = [
            "scenario": scenario, "source": source, "complete": candidate.complete,
            "feasible": candidate.feasible,
            "order": candidate.legs.filter { !$0.isReturn }.map { $0.to.title },
            "orderIDs": candidate.order, "travelSeconds": candidate.travelMinutes * 60,
            "waitingSeconds": candidate.waitingMinutes * 60, "dwellSeconds": candidate.dwellMinutes * 60,
            "elapsedSeconds": candidate.elapsedMinutes * 60, "requests": requests,
            "wallSeconds": wallSeconds,
            "finish": candidate.finish?.ISO8601Format() as Any? ?? NSNull(),
            "conflicts": candidate.conflicts,
            "legs": candidate.legs.map { leg in
                [
                    "from": leg.from.title, "to": leg.to.title,
                    "mode": leg.chosen?.mode.rawValue as Any? ?? NSNull(),
                    "seconds": leg.chosen?.seconds as Any? ?? NSNull(),
                    "departure": leg.departure.ISO8601Format(),
                    "arrival": leg.arrival?.ISO8601Format() as Any? ?? NSNull(),
                    "visit": leg.visit?.ISO8601Format() as Any? ?? NSNull(),
                    "leave": leg.leave?.ISO8601Format() as Any? ?? NSNull(),
                ] as [String: Any]
            },
        ]
        value.merge(extra) { _, new in new }
        try Self.append(value)
    }

    static func append(_ value: [String: Any]) throws {
        guard let path = ProcessInfo.processInfo.environment["C67_JAKARTA_METRICS"] else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(
            contentsOf: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        try handle.write(contentsOf: Data([10]))
    }
}
