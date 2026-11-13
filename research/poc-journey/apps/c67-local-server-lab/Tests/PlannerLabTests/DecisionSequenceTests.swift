import Foundation
import XCTest
@testable import PlannerEngine
import PlannerContracts

/// Exercise real lab policies; the exhaustive reference and auditor live in Python.
@MainActor final class DecisionSequenceTests: XCTestCase {
    struct Stop: Decodable { var id: String; var latitude: Double; var longitude: Double; var dwell: Int; var windows: [[Int]] }
    struct Fixture: Decodable {
        var id: String; var split: String; var family: String; var departure: Int; var deadline: Int
        var stops: [Stop]; var costs: [String: [String: Double]]; var amplitudes: [String: [String: Double]]; var unavailable: Bool
        func seconds(_ a: String, _ b: String, _ date: Date) -> Double? {
            if unavailable { return nil }
            let minute = date.timeIntervalSince1970 / 60 - 1793984400 / 60
            let peak = max(0, max(1 - abs(minute - 600) / 180, 1 - abs(minute - 1020) / 180))
            return costs[a]![b]! * (1 + amplitudes[a]![b]! * peak)
        }
        func start(_ id: String, _ date: Date) -> Date? {
            guard let stop = stops.first(where: { $0.id == id }) else { return nil }
            let relative = date.timeIntervalSince1970 - 1793984400
            let choices = stop.windows.compactMap { range -> Double? in
                let value = max(ceil((relative - 1e-7) / 900) * 900, Double(range[0] * 60))
                return value + Double(stop.dwell * 60) <= Double(range[1] * 60) + 1e-7 ? value : nil
            }
            return choices.min().map { Date(timeIntervalSince1970: 1793984400 + $0) }
        }
        func draft() -> NativeTripDraft {
            var d = NativeTripDraft.jakarta(now: Date(timeIntervalSince1970: 1793984400))
            d.departure = Date(timeIntervalSince1970: 1793984400 + Double(departure * 60))
            d.finishBy = Date(timeIntervalSince1970: 1793984400 + Double(deadline * 60))
            d.origin = .init(id: "origin", title: "Synthetic origin", query: "synthetic", latitude: -6.19, longitude: 106.82)
            d.end = d.origin; d.returnsToOrigin = true; d.rainWeight = 0
            d.routingAlgorithm = "hybrid"; d.routingAdaptive = false
            d.stops = stops.map { s in .init(point: .init(id: s.id, title: s.id, query: "synthetic", latitude: s.latitude, longitude: s.longitude),
                                             role: .visit, dwellOverride: s.dwell, exposure: .indoor,
                                             opening: .init(opensMinute: s.windows.map { $0[0] }.min(), closesMinute: s.windows.map { $0[1] }.max(), sourceNote: "SYNTHETIC fixture")) }
            return d
        }
    }
    struct Document: Decodable { var cases: [Fixture] }
    struct Observation: Encodable {
        var caseID: String; var variant: String; var candidate: NativeTripCandidate?
        var requests: Int; var cells: Int; var cpuSeconds: Double
    }
    /// Secondary budget control: no calibration, no risk trigger, fixed top-three local orders.
    func fixedThree(_ draft: NativeTripDraft, services: NativeTripAppleServices) async throws -> NativeTripReport {
        services.resetRun()
        let shortlist = LabFastPlanner.permutations(draft.stops).map {
            LabFastPlanner.estimate($0, draft: draft, visitStart: services.integrationVisitStart, forecasts: [])
        }.sorted(by: LabFastPlanner.ranked).prefix(3)
        var values: [NativeTripCandidate] = []
        for next in shortlist {
            let value = try await NativeTripEngine.evaluate(next.order, draft: draft, services: services, forecasts: [], progress: { _ in })
            values.append(value)
            if value.legs.contains(where: { $0.chosen?.usable != true }) { break }
        }
        return .init(draft: draft, candidates: values, fastest: values.min(by: NativeTripCandidate.better), weatherChoice: nil,
                     forecasts: [], requests: services.directionRequests, weatherNote: "Synthetic secondary budget control")
    }
    func testBenchmark() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["C67_DECISION_FIXTURES"], let output = env["C67_DECISION_OUTPUT"] else {
            throw XCTSkip("Explicit fixture/output paths required for this experiment")
        }
        let fixtures = try JSONDecoder().decode(Document.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        let split = env["C67_DECISION_SPLIT"] ?? "development"
        let variants = (env["C67_DECISION_VARIANTS"] ?? "C,D").split(separator: ",").map(String.init)
        var observations: [Observation] = []
        let outputURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for f in fixtures.cases where f.split == split {
            for variant in variants {
                let logs = NativeTripLogStore(directory: outputURL.deletingLastPathComponent().appendingPathComponent("traces/\(f.id)/\(variant)"), maximumFiles: 2, maximumBytes: 300000)
                let s = NativeTripAppleServices(logs: logs, requestLimit: 512)
                s.integrationForecasts = []; s.integrationVisitStart = { f.start($0, $1) }
                var calls = 0; var cells = 0
                s.integrationETA = { a, b, m, date in
                    calls += 1; cells += 1
                    let seconds = f.seconds(a.id, b.id, date)
                    return .init(id: a.id + ">" + b.id, mode: m, seconds: seconds, distance: 1000, expectedDeparture: date,
                                 expectedArrival: seconds.map { date.addingTimeInterval($0) }, status: seconds == nil ? "unavailable" : "available", note: "Independent directed synthetic fixture")
                }
                if variant == "C" {
                    s.labBatch = { queries in
                        calls += 1; cells += queries.count
                        return queries.map { q in
                            .init(query: q, seconds: f.seconds(q.fromID, q.toID, q.departure), distance: 1000,
                                  status: f.unavailable ? "unavailable" : "available", note: "Independent synthetic snapshot")
                        }
                    }
                }
                let began = ContinuousClock.now
                let report: NativeTripReport
                switch variant {
                case "C": report = try await NativeTripTimeAwarePlanner.plan(f.draft(), services: s, progress: { _ in })
                case "D": report = try await LabFastPlanner.plan(f.draft(), services: s, progress: { _ in })
                case "E2": report = try await LabSelectivePlanner.plan(f.draft(), services: s, maximumValidations: 2, progress: { _ in })
                case "E3": report = try await LabSelectivePlanner.plan(f.draft(), services: s, maximumValidations: 3, progress: { _ in })
                case "F3": report = try await fixedThree(f.draft(), services: s)
                default: throw NSError(domain: "Unsupported experiment policy", code: 1)
                }
                let duration = began.duration(to: .now).components
                observations.append(.init(caseID: f.id, variant: variant, candidate: report.fastest ?? report.candidates.sorted(by: NativeTripCandidate.better).first,
                                          requests: calls, cells: cells, cpuSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18))
                try LabJSON.encoder().encode(observations).write(to: outputURL, options: .atomic)
            }
        }
        XCTAssertFalse(observations.isEmpty)
        print("DECISION_SEQUENCE observations=\(observations.count) split=\(split)")
    }
}
