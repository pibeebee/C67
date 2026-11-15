import Foundation
import Observation
import TripIntelligence

@MainActor @Observable final class RecommendationModel {
    var brief = RecommendationBriefV1() { didSet { if !restoring { invalidate(correction: true) } } }
    var result: RecommendationRunV1?
    var history: [RecommendationRunV1] = []
    var runtime: ModelRuntime?
    var fixture = ProcessInfo.processInfo.arguments.contains("--fixture-ui")
    var busy = false
    var progress = ""
    var error = ""
    var exportURL: URL?
    var submissions = 0
    var corrections = 0
    private var restoring = false
    private var task: Task<Void, Never>?
    private let revision = RunRevision()
    private let store = RecommendationStore(
        directory: LabStore.defaultDirectory(
            testing: ProcessInfo.processInfo.arguments.contains("--fixture-ui")
                || ProcessInfo.processInfo.arguments.contains("--recommendation-smoke")
        )
        .appendingPathComponent("Recommendations-v1"))

    func load() async {
        runtime = await FoundationModelEngine().runtime()
        do {
            history = try await store.runs()
            if var profile = try await store.profile() {
                profile.date = RecommendationBriefV1.today()
                brief = profile
            }
            if fixture { brief.date = "2026-11-05" }
        } catch { self.error = "Pemulihan: \(error.localizedDescription)" }
        if ProcessInfo.processInfo.arguments.contains("--recommendation-smoke") {
            brief = RecommendationExamples.brief()
            generate()
        }
    }
    func invalidate(correction: Bool = false) {
        revision.advance()
        task?.cancel()
        task = nil
        busy = false
        exportURL = nil
        if correction && result != nil { corrections += 1 }
        result = nil
    }
    func toggle(_ experience: Experience) {
        if brief.experiences.contains(experience) {
            brief.experiences.removeAll { $0 == experience }
        } else {
            brief.experiences.append(experience)
            brief.avoids.removeAll { $0 == experience }
        }
    }
    func add(_ candidate: CandidateV1) {
        guard brief.places.count < 6, !brief.places.contains(where: { $0.id == candidate.id }) else {
            return
        }
        brief.places.append(candidate)
    }
    func example() { brief = RecommendationExamples.brief(knownPlaces: brief.hasPlaces) }
    func saveProfile() async {
        do { try await store.saveProfile(brief) } catch { self.error = error.localizedDescription }
    }
    func restore(_ run: RecommendationRunV1) {
        invalidate()
        restoring = true
        brief = run.brief
        result = run
        restoring = false
    }
    func useImported(_ context: TripContextV1) {
        var value = brief
        value.hasPlaces = true
        value.date = String(context.departure.prefix(10))
        if let date = Codec.date(context.departure) {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
            formatter.dateFormat = "yyyy-MM-dd"
            value.date = formatter.string(from: date)
        }
        value.places = context.stops.map { stop in
            CandidateV1(place: stop.place, evidence: context.evidence.filter { $0.subjectID == stop.id })
        }
        brief = value
    }
    func alternatives() {
        guard let result, !brief.hasPlaces else { return }
        let ids = result.selectedIDs.isEmpty ? result.advice.map(\.id) : result.selectedIDs
        brief.excludedIDs = Array(Set(brief.excludedIDs + ids))
        generate()
    }
    func generate(baseline: Bool = false) {
        invalidate()
        let token = revision.value
        let input = brief
        do { try input.validate() } catch {
            self.error = error.localizedDescription
            return
        }
        busy = true
        error = ""
        progress = "Menyiapkan rekomendasi"
        submissions += 1
        let pipeline = RecommendationPipeline(
            model: fixture ? FixtureModelEngine() : FoundationModelEngine(),
            search: fixture ? RecommendationFixtureSearch() : RecommendationMapSearch())
        task = Task {
            do {
                var run = try await pipeline.run(brief: input, useModel: !baseline) { message in
                    await MainActor.run { if self.revision.accepts(token) { self.progress = message } }
                }
                try Task.checkCancellation()
                guard revision.accepts(token) else { return }
                run.inputSubmissions = submissions
                run.correctionRounds = corrections
                try await store.save(run)
                try Task.checkCancellation()
                guard revision.accepts(token) else { return }
                result = run
                history = try await store.runs()
                busy = false
                if ProcessInfo.processInfo.arguments.contains("--recommendation-smoke") {
                    FileHandle.standardOutput.write(
                        Data(
                            ("FM_RECOMMENDATIONS_BEGIN\n" + (try Codec.text(run)) + "\nFM_RECOMMENDATIONS_END\n")
                                .utf8))
                }
            } catch is CancellationError { if revision.accepts(token) { busy = false } } catch {
                if revision.accepts(token) {
                    self.error = error.localizedDescription
                    busy = false
                }
            }
        }
    }
    func cancel() {
        invalidate()
        error = "Dibatalkan; pilihan Anda tetap tersedia."
    }
    func export() {
        guard let result else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "FM-Recommendations-" + result.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("recommendations.json")
            try Codec.encode(result).write(to: url, options: .atomic)
            try result.markdown.write(
                to: directory.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
            exportURL = url
        } catch { self.error = error.localizedDescription }
    }
}
