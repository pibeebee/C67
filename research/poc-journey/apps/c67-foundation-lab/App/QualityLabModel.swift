import Foundation
import Observation
import PreferenceQuality

@MainActor @Observable final class QualityLabModel {
    var catalog: QualityCatalog?
    var profile = QualityProfile() { didSet { if !restoring { changed() } } }
    var run: QualityRun?
    var history: [QualityRun] = []
    var busy = false
    var progress = ""
    var error = ""
    var exportFolder: URL?
    var edits = 0
    var corrections = 0
    var questions = 0
    var proposal: QualityProfile?
    var mapChecks: [QualityMapCheck] = []
    private let store: QualityStore
    private let pipeline = QualityPipeline()
    private var task: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var revision = 0
    private var loaded = false
    private var restoring = false
    init() {
        let test =
            ProcessInfo.processInfo.arguments.contains("--quality-ui")
                || ProcessInfo.processInfo.arguments.contains("--quality-smoke")
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(test ? "C67Quality-Tests" : "C67Quality-v1")
        store = QualityStore(directory: folder)
    }
    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let catalog = try QualityCatalog.load()
            self.catalog = catalog
            restoring = true
            do { profile = try await store.profile(catalog: catalog) } catch {
                self.error = "Profil tidak terbaca; berkas dipertahankan dan pilihan awal dipakai."
            }
            restoring = false
            let saved = try await store.history()
            history = saved.runs
            if saved.unreadable > 0 { error = "\(saved.unreadable) riwayat rusak dipertahankan." }
            if ProcessInfo.processInfo.arguments.contains("--quality-reset") { profile = .init() }
            if ProcessInfo.processInfo.arguments.contains("--quality-smoke") {
                preset("coffee-soft-reading")
                compare()
            }
        } catch { self.error = error.localizedDescription }
    }
    private func invalidate() {
        revision += 1
        task?.cancel()
        task = nil
        run = nil
        proposal = nil
        busy = false
        exportFolder = nil
        mapChecks = []
    }
    private func changed() {
        if run != nil { corrections += 1 }
        edits += 1
        invalidate()
        error = ""
        guard let catalog else { return }
        let value = profile
        let token = revision
        saving?.cancel()
        saving = Task {
            do {
                try Task.checkCancellation()
                try await store.saveProfile(value, catalog: catalog)
            } catch is CancellationError {} catch {
                if token == revision { self.error = error.localizedDescription }
            }
        }
    }
    func set(_ feature: QualityFeature, mode: String) {
        var value = profile
        value.must.remove(feature)
        value.prefer.remove(feature)
        value.avoid.remove(feature)
        switch mode {
        case "must": value.must.insert(feature)
        case "prefer": value.prefer.insert(feature)
        case "avoid": value.avoid.insert(feature)
        default: break
        }
        profile = value
    }
    func preset(_ id: String) {
        do {
            if let item = try QualityCase.load().first(where: { $0.id == id }) { profile = item.profile }
        } catch { self.error = error.localizedDescription }
    }
    func reviewDirection() {
        questions += 1
        proposal = DirectionReview.propose(profile.direction, current: profile)
        if proposal == nil {
            error =
                "Arahan memerlukan pilihan terstruktur. Negasi, koreksi, harga dan keramaian tidak ditebak."
        }
    }
    func acceptProposal() {
        if let proposal { profile = proposal }
        proposal = nil
    }
    func confirmControls() {
        var value = profile
        value.directionConfirmed = true
        profile = value
    }
    func like(_ id: String, feature: QualityFeature) {
        var value = profile
        value.likedID = id
        value.likedFeature = feature
        profile = value
    }
    func dismiss(_ id: String) {
        var value = profile
        value.excludedIDs.insert(id)
        profile = value
    }
    func compare() {
        guard let catalog else { return }
        invalidate()
        let token = revision
        let value = profile
        let counters = (edits, corrections, questions)
        busy = true
        error = ""
        progress = "Memeriksa fakta dan kebutuhan…"
        task = Task {
            do {
                var result = try await pipeline.run(profile: value, catalog: catalog) { message in
                    await MainActor.run { if self.revision == token { self.progress = message } }
                }
                try Task.checkCancellation()
                guard token == revision else { return }
                result.inputChanges = counters.0
                result.userCorrections = counters.1
                result.followupQuestions = counters.2
                try await store.save(result)
                let saved = try await store.history()
                guard token == revision, !Task.isCancelled else { return }
                run = result
                history = saved.runs
                busy = false
                progress = "Selesai \(String(format: "%.2f", result.elapsedSeconds)) detik"
                if ProcessInfo.processInfo.arguments.contains("--quality-smoke") {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(
                        Data(
                            ("QUALITY_BEGIN\n"
                                + String(decoding: try encoder.encode(result), as: UTF8.self) + "\nQUALITY_END\n")
                                .utf8))
                }
            } catch is CancellationError { if token == revision { busy = false } } catch {
                if token == revision {
                    busy = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func cancel() {
        invalidate()
        progress = "Dibatalkan"
    }
    func stopPending() { if busy { cancel() } }
    func verifyMap() {
        guard let run else { return }
        let ids = (run.combined.isEmpty ? run.category : run.combined).prefix(3).map(\.id)
        let candidates = ids.compactMap { id in run.catalog.candidates.first { $0.id == id } }
        let token = revision
        busy = true
        error = ""
        progress = "Memeriksa identitas di MapKit…"
        task = Task {
            do {
                let checks = try await QualityMapVerifier().verify(candidates)
                guard token == revision, !Task.isCancelled else { return }
                mapChecks = checks
                busy = false
                progress = "Pemeriksaan MapKit selesai"
            } catch is CancellationError { if token == revision { busy = false } } catch {
                if token == revision {
                    busy = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func export() async {
        guard var result = run else { return }
        result.mapChecks = mapChecks
        do { exportFolder = try await store.export(result) } catch {
            self.error = error.localizedDescription
        }
    }
    func restore(_ value: QualityRun) {
        invalidate()
        restoring = true
        profile = value.profile
        restoring = false
        run = value
        mapChecks = value.mapChecks
        progress = "Hasil tersimpan; fakta tidak diperbarui otomatis."
    }
}
