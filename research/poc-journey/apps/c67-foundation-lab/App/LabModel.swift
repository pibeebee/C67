import Foundation
import Observation
import TripIntelligence

@MainActor @Observable final class LabModel {
    var context: TripContextV1?
    var direction = UserDirection() {
        didSet { if !restoring { changed(countCorrection: true) } }
    }
    var result: ExperimentRunV1?
    var history: [ExperimentRunV1] = []
    var runtime: ModelRuntime?
    var fixtureMode = ProcessInfo.processInfo.arguments.contains("--fixture-ui")
    var running = false
    var error = ""
    var submissions = 0
    var corrections = 0
    var exportURL: URL?
    private let store = LabStore(
        directory: LabStore.defaultDirectory(
            testing: ProcessInfo.processInfo.arguments.contains("--fixture-ui")
                || ProcessInfo.processInfo.arguments.contains("--live-smoke")))
    private let revision = RunRevision()
    private var operation: Task<Void, Never>?
    private var restoring = false

    func load() async {
        runtime = await FoundationModelEngine().runtime()
        do {
            history = try await store.runs()
            direction.persistent = try await store.profile()
        } catch { self.error = "Pemulihan data: \(error.localizedDescription)" }
        if ProcessInfo.processInfo.arguments.contains("--live-smoke") {
            do {
                select(try LabFixtures.synthetic())
                direction = UserDirection(
                    text: "I prefer coffee and reading at a relaxed pace.",
                    trip: .init(interests: [.coffee, .reading]))
                generate()
            } catch { self.error = error.localizedDescription }
        }
    }
    func select(_ context: TripContextV1) {
        changed()
        self.context = context
        result = nil
        error = ""
    }
    func importFile(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            select(
                try TripImporter.load(
                    Data(contentsOf: url), source: "Imported file: \(url.lastPathComponent)"))
        } catch { self.error = error.localizedDescription }
    }
    func changed(countCorrection: Bool = false) {
        revision.advance()
        operation?.cancel()
        operation = nil
        running = false
        if countCorrection && result != nil { corrections += 1 }
        result = nil
        exportURL = nil
    }
    func cancel() {
        changed()
        error = "Dibatalkan. Snapshot asli tetap tersedia."
    }
    func toggle(_ interest: Interest, persistent: Bool) {
        if persistent {
            if direction.persistent.interests.contains(interest) {
                direction.persistent.interests.removeAll { $0 == interest }
            } else {
                direction.persistent.interests.append(interest)
                direction.persistent.avoids.removeAll { $0 == interest }
            }
        } else {
            if direction.trip.interests.contains(interest) {
                direction.trip.interests.removeAll { $0 == interest }
            } else {
                direction.trip.interests.append(interest)
                direction.trip.avoids.removeAll { $0 == interest }
            }
        }
    }
    func saveProfile() async {
        do { try await store.saveProfile(direction.persistent) } catch {
            self.error = "Profil belum disimpan: \(error.localizedDescription)"
        }
    }
    func generate(baseline: Bool = false) {
        guard let context else { return }
        changed()
        let token = revision.value
        let direction = direction
        running = true
        error = ""
        submissions += 1
        let pipeline = IntelligencePipeline(
            model: fixtureMode ? FixtureModelEngine() : FoundationModelEngine(),
            search: fixtureMode ? FixturePlaceSearch() : MapKitPlaceSearch())
        operation = Task {
            do {
                var run = try await pipeline.run(
                    context: context, direction: direction, useModel: !baseline)
                try Task.checkCancellation()
                guard revision.accepts(token) else { return }
                run.inputSubmissions = submissions
                run.corrections = corrections
                try await store.save(run)
                try Task.checkCancellation()
                guard revision.accepts(token) else { return }
                result = run
                history = try await store.runs()
                running = false
                if ProcessInfo.processInfo.arguments.contains("--live-smoke") {
                    FileHandle.standardOutput.write(
                        Data(
                            ("FM_LAB_SMOKE_JSON_BEGIN\n" + (try Codec.text(run)) + "\nFM_LAB_SMOKE_JSON_END\n")
                                .utf8))
                }
            } catch is CancellationError {
                if revision.accepts(token) { running = false }
            } catch {
                if revision.accepts(token) {
                    self.error = error.localizedDescription
                    running = false
                }
            }
        }
    }
    func restore(_ run: ExperimentRunV1) {
        changed()
        restoring = true
        context = run.context
        direction = run.direction
        result = run
        restoring = false
    }
    func export() {
        guard let result else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "C67FoundationLab-\(result.id)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let jsonURL = directory.appendingPathComponent("run.json")
            try Codec.encode(result).write(to: jsonURL, options: .atomic)
            try result.markdown.write(
                to: directory.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
            exportURL = jsonURL
        } catch { self.error = "Ekspor gagal: \(error.localizedDescription)" }
    }
}
