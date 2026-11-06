import Foundation
import Observation

@MainActor @Observable final class WeatherLabModel {
    var points = WeatherLabPoint.samples
    var selected = Set(WeatherLabPoint.samples.map(\.id))
    var mode = WeatherLabMode.automatic
    var start = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 3_600) * 3_600)
    var end = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 3_600) * 3_600 + 6 * 3_600)
    private(set) var results: [WeatherLabResult] = []
    private(set) var events: [WeatherLabEvent] = []
    private(set) var stats = WeatherLabStats()
    private(set) var isRunning = false
    private(set) var status = "Belum dijalankan. Tidak ada request otomatis."
    private(set) var authBlocked = false
    private(set) var cacheCount = 0
    private(set) var reportJSON = ""
    private(set) var reportURL: URL?
    private(set) var resultWindow: WeatherLabWindow?
    private(set) var runIsProbe = false
    let simulated: Bool
    @ObservationIgnored private let engine: WeatherLabEngine
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var requestedMode: WeatherLabMode?
    @ObservationIgnored private var requestedGroups: [WeatherLabGroup] = []
    @ObservationIgnored private let reportDirectory: URL
    @ObservationIgnored private let loadSavedDraft: () throws -> NativeTripDraft?

    init(engine: WeatherLabEngine? = nil, simulated: Bool = false, reportDirectory: URL? = nil,
         loadSavedDraft: (() throws -> NativeTripDraft?)? = nil) {
        self.simulated = simulated
        self.loadSavedDraft = loadSavedDraft ?? { try NativeTripLocalStore().load().session?.draft }
        self.reportDirectory = reportDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("C67WeatherLabReports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        if let engine { self.engine = engine }
        else {
            #if DEBUG
                self.engine = WeatherLabEngine(service: simulated ? WeatherLabDemoProvider() as any WeatherLabProvider : WeatherLabLiveProvider())
            #else
                self.engine = WeatherLabEngine(service: WeatherLabLiveProvider())
            #endif
        }
        self.engine.onEvent = { [weak self] message in self?.record(message) }
    }
    var groups: [WeatherLabGroup] { (try? WeatherLabGroup.make(points.filter { selected.contains($0.id) })) ?? [] }

    func run(probe: Bool = false, refresh: Bool = false) {
        guard !isRunning else { return }
        do {
            let window = WeatherLabWindow(start: start, end: end)
            try window.validate()
            let all = try WeatherLabGroup.make(points.filter { selected.contains($0.id) })
            // One-point diagnosis uses one actual point, without grouping, cache or fallback.
            let targets = probe ? [WeatherLabGroup(representative: all[0].representative, members: [all[0].representative])] : all
            generation = UUID(); let run = generation
            isRunning = true; status = probe ? "Menguji satu titik WeatherKit…" : "Mengambil prakiraan per kelompok…"
            results = []; events = []; stats = .init(); reportJSON = ""; reportURL = nil
            resultWindow = window; runIsProbe = probe; startedAt = .now
            requestedMode = probe ? .weatherKitOnly : mode; requestedGroups = targets
            record(simulated ? "SIMULASI UI; tidak ada provider aktual." : "LIVE: hanya request cuaca; tidak ada pencarian/routing MapKit.")
            task = Task { [weak self, engine, mode] in
                guard let self else { return }
                do {
                    _ = try await engine.run(groups: targets, window: window, mode: mode, probe: probe, refresh: refresh) { [weak self] result in
                        guard let self, self.generation == run, !Task.isCancelled else { return }
                        self.results.append(result)
                        self.results.sort { a, b in
                            (self.requestedGroups.firstIndex { $0.id == a.id } ?? 0)
                                < (self.requestedGroups.firstIndex { $0.id == b.id } ?? 0)
                        }
                        self.syncEngine()
                    }
                    try Task.checkCancellation()
                    guard generation == run else { return }
                    let ready = results.filter { $0.payload != nil }.count
                    status = "Selesai: \(ready)/\(targets.count) kelompok memiliki prakiraan lengkap."
                } catch {
                    guard generation == run else { return }
                    status = WeatherLabError.isCancellation(error) ? "Dibatalkan. Hasil terlambat diabaikan." : error.localizedDescription
                }
                guard generation == run else { return }
                syncEngine(); isRunning = false; task = nil; updateReport()
            }
        } catch { status = error.localizedDescription }
    }

    func cancel() {
        guard isRunning else { return }
        // Keep the operation busy until cancellation unwinds. Prevent overlapping old/new engine runs.
        status = "Membatalkan…"; task?.cancel()
    }
    func resetAuthentication() { guard !isRunning else { return }; engine.resetAuthentication(); syncEngine(); updateReport() }
    func clearCache() { guard !isRunning else { return }; engine.clearCache(); syncEngine(); updateReport() }
    func toggle(_ id: String) {
        guard !isRunning else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    func useExamples() {
        guard !isRunning else { return }; points = WeatherLabPoint.samples; selected = Set(points.map(\.id))
    }
    func importSavedPlan() {
        guard !isRunning else { return }
        do {
            guard let draft = try loadSavedDraft() else {
                status = "Belum ada rencana tersimpan untuk disalin titiknya."; return
            }
            let imported = draft.allPoints.compactMap { point -> WeatherLabPoint? in
                guard let lat = point.latitude, let lon = point.longitude else { return nil }
                return .init(id: point.id, name: point.resolvedName ?? point.title, latitude: lat, longitude: lon)
            }
            guard imported.count == draft.allPoints.count else {
                status = "Ada titik rencana yang belum memiliki koordinat. Lengkapi pin di tab Rencana sebelum menyalin."; return
            }
            _ = try WeatherLabGroup.make(imported)
            points = imported; selected = Set(imported.map(\.id))
            start = draft.departure; end = draft.deadline
            status = "\(imported.count) titik disalin. Rencana tersimpan tidak diubah. Periksa tanggal sebelum menguji."
        } catch { status = "Tidak bisa menyalin titik: \(error.localizedDescription)" }
    }
    private func syncEngine() {
        stats = engine.stats; authBlocked = engine.authenticationBlocked; cacheCount = engine.cacheCount
    }
    private func record(_ message: String) {
        events.append(.init(message: message))
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
    private func updateReport() {
        struct Report: Encodable {
            let schema = 1
            var simulation: Bool
            var startedAt: Date?
            var exportedAt = Date()
            var mode: WeatherLabMode?
            var probe: Bool
            var window: WeatherLabWindow?
            var radiusMeters = 3_000
            var timeoutPerProviderSeconds = 8
            var maxConcurrentGroups = 2
            var cacheTTLSeconds = 900
            var requestedGroups: [WeatherLabGroup]
            var status: String
            var authenticationBlocked: Bool
            var stats: WeatherLabStats
            var results: [WeatherLabResult]
            var events: [WeatherLabEvent]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Report(simulation: simulated, startedAt: startedAt, mode: requestedMode,
                                                 probe: runIsProbe, window: resultWindow, requestedGroups: requestedGroups, status: status,
                                                 authenticationBlocked: authBlocked, stats: stats, results: results, events: events)) {
            reportJSON = String(decoding: data, as: UTF8.self)
            do {
                try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
                let url = reportDirectory.appendingPathComponent("weather-lab-latest.json")
                try data.write(to: url, options: .atomic)
                reportURL = url
            } catch {
                // The in-memory report remains shareable if writing the experiment-only temp file fails.
                reportURL = nil
                record("Laporan tetap di memori; berkas ekspor gagal ditulis: \(error.localizedDescription)")
            }
        }
    }
}
