import Foundation
import Testing
@testable import C67Data

private struct ReplayPeriod: Decodable { let start: Int; let end: Int; let minutes: Int; let meters: Int? }
private struct ReplayLeg: Decodable { let origin: String; let destination: String; let periods: [ReplayPeriod] }
private struct ReplayExpected: Decodable {
    let local_candidates: Int; let quote_calls: Int; let quote_budget_exhausted: Bool
    let evaluated: [V4Schedule]; let recommended: V4Schedule?
}
private struct ReplayCase: Decodable { let case_id: String; let trip: V4Trip; let synthetic_network: [ReplayLeg]; let result: ReplayExpected }

@Test func v4NativePortReplaysAllPythonBoundedFixtures() async throws {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("V4Replay.json")
    let cases = try JSONDecoder().decode([ReplayCase].self, from: Data(contentsOf: path))
    #expect(cases.count == 17)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    for item in cases {
        func lookup(_ from: String, _ to: String, _ at: Int, proxy: Bool) -> V4Quote {
            guard let leg = item.synthetic_network.first(where: { $0.origin == from && $0.destination == to }) else {
                return .init(minutes: nil, meters: nil, status: proxy ? "missing_proxy" : "missing_synthetic_quote")
            }
            let periods = leg.periods.sorted { $0.start < $1.start }
            let period = proxy ? periods.first : periods.first { $0.start <= at && at < $0.end }
            guard let period else { return .init(minutes: nil, meters: nil, status: proxy ? "missing_proxy" : "missing_synthetic_quote") }
            return .init(minutes: period.minutes, meters: period.meters, status: proxy ? "synthetic_static_proxy" : "synthetic_quote")
        }
        let result = try await V4Planner.search(item.trip, proxy: { lookup($0, $1, $2, proxy: true) }, quote: { lookup($0, $1, $2, proxy: false) })
        #expect(result.localCandidates == item.result.local_candidates, "\(item.case_id) domain")
        #expect(result.quoteCalls == item.result.quote_calls, "\(item.case_id) quotes")
        #expect(result.exhausted == item.result.quote_budget_exhausted, "\(item.case_id) budget")
        #expect(try encoder.encode(result.evaluated) == encoder.encode(item.result.evaluated), "\(item.case_id) evaluated schedules")
        #expect(try encoder.encode(result.recommended) == encoder.encode(item.result.recommended), "\(item.case_id) recommendation")
    }
}

private struct ExhaustiveExpected: Decodable {
    let local_candidates: Int; let quote_calls: Int; let quote_budget_exhausted: Bool; let recommended: V4Schedule?
}
private struct ExhaustiveCase: Decodable { let case_id: String; let trip: V4Trip; let synthetic_network: [ReplayLeg]; let result: ExhaustiveExpected }

@Test func v4NativePortReplaysAllPythonExhaustiveFixtures() async throws {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("V4ExhaustiveReplay.json")
    let cases = try JSONDecoder().decode([ExhaustiveCase].self, from: Data(contentsOf: path))
    #expect(cases.count == 17)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    for item in cases {
        let result = try await V4Planner.search(item.trip, quoteLimit: nil, bounded: false, proxy: { _, _, _ in
            .init(minutes: nil, meters: nil, status: "unused")
        }, quote: { from, to, at in
            let periods = item.synthetic_network.first { $0.origin == from && $0.destination == to }?.periods ?? []
            guard let p = periods.first(where: { $0.start <= at && at < $0.end }) else { return .init(minutes: nil, meters: nil, status: "missing_synthetic_quote") }
            return .init(minutes: p.minutes, meters: p.meters, status: "synthetic_quote")
        })
        #expect(result.localCandidates == item.result.local_candidates, "\(item.case_id) domain")
        #expect(result.quoteCalls == item.result.quote_calls, "\(item.case_id) quotes")
        #expect(result.exhausted == item.result.quote_budget_exhausted, "\(item.case_id) budget")
        #expect(try encoder.encode(result.recommended) == encoder.encode(item.result.recommended), "\(item.case_id) recommendation")
    }
}
