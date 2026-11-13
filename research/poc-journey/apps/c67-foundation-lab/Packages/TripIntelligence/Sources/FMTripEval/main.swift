import Foundation
import TripIntelligence

@main struct FMTripEval {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let engine = FoundationModelEngine()
            let command = args.first ?? "inspect"
            func option(_ key: String) -> String? {
                guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            func output<T: Encodable>(_ value: T) throws { print(try Codec.text(value)) }
            switch command {
            case "recommend":
                let brief: RecommendationBriefV1
                if let path = option("--input") {
                    brief = try JSONDecoder().decode(
                        RecommendationBriefV1.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                } else {
                    var value = RecommendationExamples.brief(knownPlaces: args.contains("--known"))
                    if !args.contains("--fixture") && !args.contains("--known") {
                        value.date = RecommendationBriefV1.today()
                    }
                    value.text = option("--text") ?? ""
                    brief = value
                }
                let search: any RecommendationSearching
                if let path = option("--search-snapshot") {
                    let saved = try JSONDecoder().decode(
                        RecommendationRunV1.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                    search = RecommendationReplaySearch(batch: saved.search)
                } else {
                    search =
                        args.contains("--fixture") || args.contains("--synthetic-search")
                            ? RecommendationFixtureSearch() : RecommendationMapSearch()
                }
                let model: any ModelGenerating = args.contains("--fixture") ? FixtureModelEngine() : engine
                let run = try await RecommendationPipeline(model: model, search: search).run(
                    brief: brief, useModel: !args.contains("--baseline"))
                if let path = option("--out") {
                    let url = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try Codec.encode(run).write(
                        to: url.appendingPathComponent("recommendations.json"), options: .atomic)
                    try run.markdown.write(
                        to: url.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
                }
                try output(run)
            case "inspect": try output(await engine.runtime())
            case "evaluate-one":
                guard let path = option("--input") else { throw LabError.invalid("--input required") }
                let input = try JSONDecoder().decode(
                    EvaluationInput.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                let attempt = try await EvaluationRunner.attempt(input, model: engine)
                if let path = option("--out") {
                    try Codec.encode(attempt).write(to: URL(fileURLWithPath: path), options: .atomic)
                }
                try output(attempt)
            case "schema":
                guard let name = option("--capability"), let capability = Capability(rawValue: name) else {
                    throw LabError.invalid("--capability required")
                }
                print(String(describing: LabPrompts.schema(capability)))
            case "context":
                let context: TripContextV1
                if let path = option("--input") {
                    context = try TripImporter.load(Data(contentsOf: URL(fileURLWithPath: path)))
                } else {
                    context = try LabFixtures.synthetic()
                }
                try output(context)
            case "pipeline":
                let context =
                    try option("--input").map {
                        try TripImporter.load(Data(contentsOf: URL(fileURLWithPath: $0)))
                    } ?? LabFixtures.synthetic()
                let model: any ModelGenerating = args.contains("--fixture") ? FixtureModelEngine() : engine
                let search: any PlaceSearching =
                    args.contains("--live-search") ? MapKitPlaceSearch() : FixturePlaceSearch()
                let direction = UserDirection(
                    text: option("--text") ?? "", trip: .init(interests: [.coffee, .reading]))
                let pipeline = IntelligencePipeline(model: model, search: search)
                let run = try await pipeline.run(
                    context: context, direction: direction, useModel: !args.contains("--baseline"))
                if let path = option("--out") {
                    let directory = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try Codec.encode(run).write(
                        to: directory.appendingPathComponent("run.json"), options: .atomic)
                    try run.markdown.write(
                        to: directory.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
                }
                try output(run)
            default: throw LabError.invalid("Commands: inspect, context, schema, pipeline")
            }
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(String(describing: error))\n".utf8))
            exit(1)
        }
    }
}
