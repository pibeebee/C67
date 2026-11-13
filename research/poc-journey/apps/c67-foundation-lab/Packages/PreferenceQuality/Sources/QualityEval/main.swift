import Foundation
import PreferenceQuality

@main struct QualityEval {
    static func main() async throws {
        let args = CommandLine.arguments
        func option(_ name: String, fallback: String) -> String {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return fallback }
            return args[index + 1]
        }
        let out = URL(fileURLWithPath: option("--out", fallback: "/tmp/c67-quality-eval"))
        let store = QualityStore(directory: out)
        let catalog = try QualityCatalog.load()
        let cases = try QualityCase.load()
        let selected =
            args.contains("--all")
                ? cases
                : cases.filter { $0.id == option("--case", fallback: "coffee-reading") }
        guard !selected.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        let pipeline = QualityPipeline()
        var summaries: [[String: String]] = []
        for item in selected {
            var run = try await pipeline.run(
                profile: item.profile, catalog: catalog,
                useEmbedding: !args.contains("--baseline"))
            if args.contains("--verify-map") {
                let ids = (run.combined.isEmpty ? run.category : run.combined).prefix(3).map(\.id)
                let candidates = ids.compactMap { id in catalog.candidates.first { $0.id == id } }
                run.mapChecks = try await QualityMapVerifier().verify(candidates)
            }
            try await store.save(run)
            _ = try await store.export(run)
            let eligible = Set(run.decisions.filter { $0.state == "eligible" }.map(\.id))
            let ids = run.combined.prefix(3).map(\.id).joined(separator: ",")
            let correctGate =
                eligible == Set(item.expectedEligible)
                    && (item.expectedReview == (run.status == "preference_review_required"))
            summaries.append([
                "case": item.id, "runID": run.id.uuidString, "status": run.status,
                "gatePassed": String(correctGate), "combinedTop3": ids,
                "seconds": String(run.elapsedSeconds),
            ])
            print("\(item.id) \(run.status) gate=\(correctGate) combined=\(ids)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try encoder.encode(summaries).write(to: out.appendingPathComponent("series-summary.json"))
    }
}
