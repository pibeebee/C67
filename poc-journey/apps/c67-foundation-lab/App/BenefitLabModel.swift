import Foundation
import Observation
import PreferenceQuality

@MainActor @Observable final class BenefitLabModel {
    var dataset: BenefitDataset?
    var selectedID = "currency-paraphrase" { didSet { if oldValue != selectedID { invalidate() } } }
    var run: BenefitRun?
    var history: [BenefitRun] = []
    var busy = false
    var progress = ""
    var error = ""
    var exportFolder: URL?
    private let pipeline = BenefitPipeline()
    private let store: BenefitStore
    private var task: Task<Void, Never>?
    private var revision = 0
    private var loaded = false
    init() {
        let test =
            ProcessInfo.processInfo.arguments.contains("--benefit-ui")
                || ProcessInfo.processInfo.arguments.contains("--benefit-smoke")
                || ProcessInfo.processInfo.arguments.contains("--benefit-suite")
        store = BenefitStore(
            directory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask)[0].appendingPathComponent(test ? "C67Benefit-Tests" : "C67Benefit-v1"))
    }
    var selected: BenefitCase? { dataset?.cases.first { $0.id == selectedID } }
    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            dataset = try BenefitDataset.load()
            let saved = try await store.history()
            history = saved.runs
            if saved.unreadable > 0 { error = "\(saved.unreadable) berkas rusak dipertahankan." }
            if ProcessInfo.processInfo.arguments.contains("--benefit-smoke") { compare() }
            if ProcessInfo.processInfo.arguments.contains("--benefit-suite") { runSuite() }
        } catch { self.error = error.localizedDescription }
    }
    func invalidate() {
        revision += 1
        task?.cancel()
        task = nil
        busy = false
        run = nil
        exportFolder = nil
        error = ""
    }
    private func runSuite() {
        guard let dataset else { return }
        invalidate()
        busy = true
        let token = revision
        task = Task {
            do {
                var results: [BenefitRun] = []
                for item in dataset.cases {
                    try Task.checkCancellation()
                    let result = try await pipeline.run(
                        item: item, dataset: dataset, now: dataset.snapshotClock)
                    guard token == revision else { return }
                    try await store.save(result)
                    results.append(result)
                    progress = "\(results.count)/\(dataset.cases.count) · \(item.id)"
                }
                try Task.checkCancellation()
                guard token == revision else { return }
                print("C67_BENEFIT_SERIES_BEGIN")
                print(String(decoding: try BenefitCodec.encode(results), as: UTF8.self))
                print("C67_BENEFIT_SERIES_END")
                run = results.first { $0.input.id == selectedID }
                history = try await store.history().runs
                busy = false
            } catch is CancellationError {
                if token == revision { busy = false }
            } catch {
                if token == revision {
                    busy = false
                    self.error = error.localizedDescription
                    print("C67_BENEFIT_ERROR \(error)")
                }
            }
        }
    }
    func compare() {
        guard let dataset, let selected else { return }
        invalidate()
        busy = true
        progress = "Memeriksa fakta, lalu kata kunci dan E5…"
        let token = revision
        task = Task {
            do {
                let result = try await pipeline.run(item: selected, dataset: dataset) { message in
                    await MainActor.run { if self.revision == token { self.progress = message } }
                }
                try Task.checkCancellation()
                guard revision == token else { return }
                try await store.save(result)
                let saved = try await store.history()
                guard revision == token, !Task.isCancelled else { return }
                run = result
                history = saved.runs
                busy = false
                if ProcessInfo.processInfo.arguments.contains("--benefit-smoke") {
                    print("C67_BENEFIT_BEGIN")
                    print(String(decoding: try BenefitCodec.encode(result), as: UTF8.self))
                    print("C67_BENEFIT_END")
                }
            } catch is CancellationError {
                if revision == token { busy = false }
            } catch {
                if revision == token {
                    busy = false
                    self.error = error.localizedDescription
                    print("C67_BENEFIT_ERROR \(error)")
                }
            }
        }
    }
    func restore(_ value: BenefitRun) {
        invalidate()
        selectedID = value.input.id
        run = value
    }
    func export() {
        guard let run else { return }
        let token = revision
        Task {
            do {
                let folder = try await store.export(run)
                if revision == token { exportFolder = folder }
            } catch { if revision == token { self.error = error.localizedDescription } }
        }
    }
}
