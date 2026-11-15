import Foundation
import Observation
import PreferenceLearning
import TripIntelligence

@MainActor @Observable final class PreferenceLabModel {
    var catalogID = "mapkit-live-v1"
    var catalog: PreferenceCatalog?
    var profile = LocalPreferenceProfile() { didSet { if !restoring { changed() } } }
    var run: PreferenceComparisonRun?
    var history: [PreferenceComparisonRun] = []
    var busy = false
    var progress = ""
    var error = ""
    var exportURL: URL?
    var modelStatus = "Model lokal E5 · pemeriksaan dilakukan saat digunakan"
    private let embedding = E5Embedding()
    private let store = PreferenceStore(
        directory: LabStore.defaultDirectory(
            testing: ProcessInfo.processInfo.arguments.contains("--preference-ui")
                || ProcessInfo.processInfo.arguments.contains("--preference-smoke")
                || ProcessInfo.processInfo.arguments.contains("--preference-live-smoke")
                || ProcessInfo.processInfo.arguments.contains("--preference-live-fixture")
        ).appendingPathComponent("PreferenceLearning-v1"))
    private var restoring = false
    private var loaded = false
    private var revision = 0
    private var task: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    func load() async {
        guard !loaded else { return }
        loaded = true
        if ProcessInfo.processInfo.arguments.contains("--preference-ui")
            || ProcessInfo.processInfo.arguments.contains("--preference-smoke")
        {
            catalogID = "synthetic-v1"
        }
        await switchCatalog(catalogID)
        if ProcessInfo.processInfo.arguments.contains("--preference-reset") {
            profile = .init()
        }
        if ProcessInfo.processInfo.arguments.contains("--preference-live-smoke") {
            profile = .init()
            profile.interests = [.coffee, .reading]
            profile.text = "Saya ingin ngopi sambil membaca"
            compare()
        }
        if ProcessInfo.processInfo.arguments.contains("--preference-smoke") {
            profile.text = "Saya ingin ngopi sambil membaca di tempat yang tenang"
            compare()
        }
    }
    func switchCatalog(_ id: String) async {
        invalidate()
        saveTask?.cancel()
        let token = revision
        do {
            let value = try PreferenceCatalog.load(id)
            var saved: LocalPreferenceProfile
            var recoveryNote = ""
            do { saved = try await store.profile(catalogID: id) } catch {
                saved = .init()
                recoveryNote =
                    "Profil tersimpan tidak dapat dibaca; pilihan awal digunakan. Berkas lama tetap dipertahankan."
            }
            let savedHistory = try await store.runs()
            guard revision == token else { return }
            do { try saved.validate(catalog: value) } catch {
                saved = .init()
                self.error = "Profil lama tidak sesuai katalog; pilihan awal digunakan."
            }
            restoring = true
            catalogID = id
            catalog = value
            profile = saved
            history = savedHistory
            if !recoveryNote.isEmpty { error = recoveryNote }
            restoring = false
        } catch { if revision == token { self.error = error.localizedDescription } }
    }
    private func invalidate() {
        revision += 1
        task?.cancel()
        task = nil
        busy = false
        run = nil
        exportURL = nil
    }
    private func changed() {
        invalidate()
        error = ""
        saveTask?.cancel()
        let value = profile
        let id = catalogID
        saveTask = Task {
            do {
                try Task.checkCancellation()
                try await store.save(value, catalogID: id)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func toggleInterest(_ tag: PreferenceTag) {
        var value = profile
        if value.interests.contains(tag) {
            value.interests.remove(tag)
        } else {
            value.interests.insert(tag)
            value.avoids.remove(tag)
        }
        profile = value
    }
    func toggleAvoid(_ tag: PreferenceTag) {
        var value = profile
        if value.avoids.contains(tag) {
            value.avoids.remove(tag)
        } else {
            value.avoids.insert(tag)
            value.interests.remove(tag)
        }
        profile = value
    }
    func feedback(_ place: PreferencePlace, _ choice: PlaceFeedback) {
        var value = profile
        if value.feedback[place.id] == choice {
            value.setFeedback(nil, for: place, remember: catalogID == "mapkit-live-v1")
        } else {
            if choice == .liked, value.feedback.values.filter({ $0 == .liked }).count >= 6 {
                error = "Maksimal enam tempat disukai pada eksperimen ini."
                return
            }
            if value.feedback.count >= 100 && value.feedback[place.id] == nil {
                error = "Batas 100 pilihan tersimpan tercapai; hapus pilihan lama atau reset profil lab."
                return
            }
            value.setFeedback(choice, for: place, remember: catalogID == "mapkit-live-v1")
        }
        profile = value
    }
    func reset() { profile = .init() }
    func compare(baselineOnly: Bool = false) {
        guard let catalog else { return }
        invalidate()
        let token = revision
        let input = profile
        busy = true
        error = ""
        progress = "Menyiapkan perbandingan"
        task = Task {
            do {
                let update: @Sendable (String) async -> Void = { message in
                    await MainActor.run { if self.revision == token { self.progress = message } }
                }
                let value: PreferenceComparisonRun
                if catalog.id == "mapkit-live-v1" {
                    let search: any PreferencePlaceSearching =
                        ProcessInfo.processInfo.arguments.contains("--preference-live-fixture")
                            ? PreferenceReplaySearch(
                                delay: ProcessInfo.processInfo.arguments.contains("--preference-slow-fixture")
                                    ? 2 : 0.15) : MapKitPreferenceSearch()
                    value = try await PreferenceDiscoveryPipeline(embedding: embedding, search: search).run(
                        profile: input, useEmbedding: !baselineOnly, progress: update)
                } else {
                    value = try await PreferenceRanker(embedding: embedding).compare(
                        profile: input, catalog: catalog, useEmbedding: !baselineOnly, progress: update)
                }
                try Task.checkCancellation()
                guard revision == token else { return }
                try await store.save(value)
                try Task.checkCancellation()
                guard revision == token else { return }
                self.catalog = value.catalog
                run = value
                history = try await store.runs()
                busy = false
                modelStatus = value.embedding?.runtime ?? "Model tidak dipakai / pembanding kategori"
                if ProcessInfo.processInfo.arguments.contains("--preference-smoke")
                    || ProcessInfo.processInfo.arguments.contains("--preference-live-smoke")
                {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                    let text = String(decoding: try encoder.encode(value), as: UTF8.self)
                    FileHandle.standardOutput.write(
                        Data(("PREFERENCE_LAB_BEGIN\n" + text + "\nPREFERENCE_LAB_END\n").utf8))
                }
            } catch is CancellationError { if revision == token { busy = false } } catch {
                if revision == token {
                    self.error = error.localizedDescription
                    busy = false
                }
            }
        }
    }
    var feedbackPlaces: [PreferencePlace] {
        guard let catalog else { return [] }
        return profile.knownPlaces(catalog: catalog)
    }
    func cancel() {
        invalidate()
        progress = "Dibatalkan"
    }
    func restore(_ value: PreferenceComparisonRun) {
        invalidate()
        restoring = true
        catalogID = value.catalog.id
        catalog = value.catalog
        profile = value.profile
        run = value
        restoring = false
    }
    func export() {
        guard let run else { return }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "Preference-Lab-" + run.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = folder.appendingPathComponent("run.json")
            try encoder.encode(run).write(to: url, options: .atomic)
            try run.markdown.write(
                to: folder.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
            exportURL = url
        } catch { self.error = error.localizedDescription }
    }
}
