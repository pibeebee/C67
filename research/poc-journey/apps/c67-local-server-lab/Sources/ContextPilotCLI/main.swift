import Foundation
import PlaceContextEngine
import PlannerEngine
import ContextPilotAdapters

func wall(_ began: ContinuousClock.Instant) -> Double {
    let c = began.duration(to: .now).components; return Double(c.seconds) + Double(c.attoseconds) / 1e18
}
struct FixtureCase: Codable {
    var id: String; var split: String; var family: String; var now: Date; var input: ContextPlanRequest
    var nodeIDs: [String]; var matrix: [[Double]]; var peakAfter: Date; var peakExtra: Double
}
struct FixtureFile: Codable { var cases: [FixtureCase] }
@MainActor final class FixtureTravel: ContextTravelProvider {
    let c: FixtureCase
    init(_ c: FixtureCase) { self.c = c }
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        guard let a = c.nodeIDs.firstIndex(of: from), let b = c.nodeIDs.firstIndex(of: to) else { return nil }
        let seconds = c.matrix[a][b] + (departure >= c.peakAfter ? c.peakExtra : 0)
        return .init(seconds: seconds, departure: departure, source: "SYNTHETIC independent directed FIFO fixture")
    }
}
struct PilotRow: Codable {
    var caseID: String; var split: String; var family: String; var ablation: String; var policy: String; var budget: Int
    var processingSeconds: Double; var etaWallSeconds: Double; var result: ContextItineraryResult
    var stopCount: Int? = nil
}
@MainActor func fixtureRun(_ file: URL, _ out: URL) async throws {
    let cases = try ContextJSON.decoder().decode(FixtureFile.self, from: Data(contentsOf: file)).cases
    var rows: [PilotRow] = []
    for c in cases {
        var configs: [(String, ContextSearchPolicy, Int)] = [("elapsed", .beam, 512), ("user", .beam, 512), ("full", .beam, 512)]
        if c.split == "holdout" { configs += (c.input.stops.count == 5 ? [24, 48, 96] : [12, 24, 48]).flatMap { cap in ContextSearchPolicy.allCases.map { ("full", $0, cap) } } }
        for (ablation, policy, cap) in configs {
            var input = c.input; input.policy = policy; input.maxTravelCalls = cap
            if ablation != "full" {
                input.priorities = [.preferredTime]
                for i in input.stops.indices {
                    input.stops[i].request.avoidRain = false; input.stops[i].request.seeksQuiet = false
                    input.stops[i].request.maximumComfortTemperatureC = nil
                    input.stops[i].request.priorities = [.preferredTime]
                    if ablation == "elapsed", input.stops[i].request.preferredTime?.required != true { input.stops[i].request.preferredTime = nil }
                }
            }
            let began = ContinuousClock.now
            var result = try await ContextItineraryPlanner.plan(input, provider: FixtureTravel(c), now: c.now)
            result.contexts = []
            rows.append(.init(caseID: c.id, split: c.split, family: c.family, ablation: ablation, policy: policy.rawValue, budget: cap, processingSeconds: wall(began), etaWallSeconds: 0, result: result))
        }
    }
    try ContextJSON.encoder().encode(rows).write(to: out, options: .atomic)
}
@main struct ContextPilotCLI {
    @MainActor static func main() async {
        do {
            let a = Array(CommandLine.arguments.dropFirst())
            if a.count == 2, a[0] == "apple-probes" {
                let budget = LabProviderBudget(callLimit: 10, cellLimit: 0)
                let apple = LabAppleREST(config: try .init(), budget: budget)
                let search = LabRESTSearch(apple: apple)
                var records: [String: [PlacePin]] = [:]
                for query in ["Wayang Museum", "Jakarta History Museum", "Fine Arts and Ceramics Museum", "Perpustakaan Jakarta Cikini", "Museum Sumpah Pemuda"] { records[query] = try await search.search(query: query) }
                try ContextJSON.encoder().encode(records).write(to: URL(fileURLWithPath: a[1]), options: .atomic)
                try ContextJSON.encoder().encode(["appleHTTPCalls": budget.calls]).write(to: URL(fileURLWithPath: a[1] + ".budget.json"), options: .atomic)
                return
            }
            if a.count == 3, a[0] == "apple-search" {
                let budget = LabProviderBudget(callLimit: 4, cellLimit: 0)
                let apple = LabAppleREST(config: try .init(), budget: budget)
                let pins = try await LabRESTSearch(apple: apple).search(query: a[1])
                try ContextJSON.encoder().encode(pins).write(to: URL(fileURLWithPath: a[2]), options: .atomic)
                try ContextJSON.encoder().encode(["appleHTTPCalls": budget.calls]).write(to: URL(fileURLWithPath: a[2] + ".budget.json"), options: .atomic)
                return
            }
            if a.count == 3, a[0] == "eta-response-probe" {
                try await ETAResponseProbe.run(trace: URL(fileURLWithPath: a[1]), output: URL(fileURLWithPath: a[2]))
                return
            }
            if a.count == 3, a[0] == "fixtures" { try await fixtureRun(URL(fileURLWithPath: a[1]), URL(fileURLWithPath: a[2])); return }
            if a.count == 3, a[0] == "five-diagnostic", let waiting = Int(a[2]), [30, 60].contains(waiting) {
                try await LivePilot.run(directory: URL(fileURLWithPath: a[1]), single: true, five: true, diagnosticWaiting: waiting); return
            }
            if a.count == 2, ["live", "single", "five", "five-single"].contains(a[0]) { try await LivePilot.run(directory: URL(fileURLWithPath: a[1]), single: a[0].hasSuffix("single"), five: a[0].hasPrefix("five")); return }
            throw ContextError.invalid("Usage: context-pilot fixtures INPUT OUTPUT | live OUTPUT_DIRECTORY | single OUTPUT_DIRECTORY | five OUTPUT_DIRECTORY | five-single OUTPUT_DIRECTORY | eta-response-probe TRACE OUTPUT")
        } catch {
            FileHandle.standardError.write(Data("context-pilot: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
