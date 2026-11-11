import Foundation
import TripIntegration

@main struct BlokMEval {
    @MainActor static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let index = args.firstIndex(of: "--out"), args.indices.contains(index + 1) else {
            throw IntegrationError.invalid("Usage: p3-blok-m-eval --out NEW_DIRECTORY [--baseline] [--include-held-out] [--live-clock] [--replay | --live-routes] [--busway]")
        }
        guard !(args.contains("--replay") && args.contains("--live-routes")) else {
            throw IntegrationError.invalid("Choose synthetic replay or live routes explicitly.")
        }
        let directory = URL(filePath: args[index + 1])
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw IntegrationError.invalid("Use a new output directory to preserve prior evidence.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = try IntegrationCatalog.load(blokM: true)
        let now = args.contains("--live-clock") ? Date.now : BlokMExperiment.snapshotClock(catalog)
        let runs = try await BlokMExperiment.recommendations(catalog: catalog, now: now,
                                                             useEmbedding: !args.contains("--baseline"),
                                                             includeHeldOut: args.contains("--include-held-out"))
        struct Series: Encodable {
            var schemaVersion = 1
            var evidence = "Sourced catalog and local recommendation inference. No live place, ETA or weather calls. Human relevance judgments pending."
            var catalogID: String
            var createdAt = Date()
            var evaluationClock: Date
            var clockMode: String
            var runs: [BlokMRecommendationRun]
        }
        let data = try IntegrationJSON.encoder().encode(Series(catalogID: catalog.quality.id, evaluationClock: now,
                                                               clockMode: args.contains("--live-clock") ? "live" : "frozen_source_snapshot", runs: runs))
        try data.write(to: directory.appendingPathComponent("series.json"), options: .atomic)
        for run in runs {
            print("\(run.persona.id) \(run.window) \(run.method): \(run.review.quality.status) top3=\(run.displayedIDs.joined(separator: ",")) factualSupport=\(run.factSupportedIDs.count)")
        }
        if !args.contains("--baseline") {
            let pipeline = IntegrationPipeline(catalog: catalog)
            var request = BlokMExperiment.request(now: now)
            request.profile = BlokMExperiment.personas[1].profile
            request.useEmbedding = true
            let cold = try await pipeline.recommend(request, now: now)
            let warm = try await pipeline.recommend(request, now: now)
            // A new pipeline owns a new E5 actor. The second identical request reuses its cache.
            try IntegrationJSON.encoder().encode([cold, warm]).write(
                to: directory.appendingPathComponent("cold-warm-recommendations.json"), options: .atomic)
        }
        if args.contains("--live-routes") {
            try await liveRoutes(catalog: catalog, directory: directory, busway: args.contains("--busway"))
        }
        #if DEBUG
            if args.contains("--replay") {
                let pipeline = try BlokMReplay.pipeline()
                let store = TripStore(directory: directory.appendingPathComponent("ReplaySession"))
                let replayNow = args.contains("--busway") ? max(BlokMExperiment.snapshotClock(catalog), try BuswayFeed.load().source.checkedAt.addingTimeInterval(1)) : BlokMExperiment.snapshotClock(catalog)
                for ids in [["bm01"], ["bm01", "bm04", "bm08"], ["bm01", "bm02", "bm03", "bm05", "bm08", "bm13"]] {
                    var request = BlokMExperiment.request(now: replayNow)
                    if args.contains("--busway") { request.transport = .transjakartaBRT }
                    request.requiredCandidateIDs = ids
                    request.desiredCount = ids.count
                    let review = try await pipeline.recommend(request, now: replayNow)
                    let prepared = try await pipeline.prepare(review, selectedIDs: ids, now: replayNow)
                    let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: replayNow)
                    try PlanAudit.validate(plan)
                    guard plan.feasible else { throw IntegrationError.invalid("Replay conflict: \(plan.conflicts)") }
                    _ = try await store.export(plan)
                    print("Replay \(ids.count) venues: feasible=\(plan.feasible), searches=\(prepared.searchRequests), travel=\(plan.travelMinutes)m")
                }
            }
        #endif
        print("Evidence directory: \(directory.path)")
    }

    @MainActor private static func liveRoutes(catalog: IntegrationCatalog, directory: URL, busway: Bool) async throws {
        struct Outcome: Encodable {
            var count: Int
            var status: String
            var detail: String
            var seconds: Double
        }
        let pipeline = IntegrationPipeline(catalog: catalog, logDirectory: directory.appendingPathComponent("ProviderLogs"))
        let store = TripStore(directory: directory.appendingPathComponent("LiveMacSession"))
        var outcomes: [Outcome] = []
        for ids in [["bm01"], ["bm01", "bm04", "bm08"], ["bm01", "bm02", "bm03", "bm05", "bm08", "bm13"]] {
            let began = Date()
            do {
                var request = BlokMExperiment.request(now: .now)
                if busway { request.transport = .transjakartaBRT }
                request.requiredCandidateIDs = ids
                request.desiredCount = ids.count
                let review = try await pipeline.recommend(request)
                let prepared = try await pipeline.prepare(review, selectedIDs: ids)
                try IntegrationJSON.encoder().encode(prepared).write(
                    to: directory.appendingPathComponent("locations-\(ids.count).json"), options: .atomic)
                guard prepared.ready else {
                    throw IntegrationError.invalid("Manual location confirmation required. Inspect locations JSON and use the app.")
                }
                let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil)
                try PlanAudit.validate(plan)
                _ = try await store.export(plan)
                let weather = plan.weather.map { "\($0.provider)/\($0.status)" }.joined(separator: ", ")
                outcomes.append(.init(count: ids.count, status: plan.feasible ? "pass" : "fail",
                                      detail: "Live Mac routing only. Weather \(weather). Conflicts \(plan.conflicts)", seconds: Date().timeIntervalSince(began)))
            } catch {
                outcomes.append(.init(count: ids.count, status: "blocked", detail: ProviderDiagnostics.message(error),
                                      seconds: Date().timeIntervalSince(began)))
            }
            try IntegrationJSON.encoder().encode(outcomes).write(to: directory.appendingPathComponent("live-mac-outcomes.json"), options: .atomic)
            print("Live Mac \(ids.count) venues: \(outcomes.last!.status) — \(outcomes.last!.detail)")
        }
    }
}
