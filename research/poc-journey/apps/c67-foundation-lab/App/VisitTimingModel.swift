import Foundation
import Observation
import VisitTiming

@MainActor @Observable final class VisitTimingModel {
    var catalog: TimingCatalog?
    var venueID = "gbk" { didSet { invalidate() } }
    var date = Date() { didSet { invalidate() } }
    var startMinute = 420 { didSet { invalidate() } }
    var endMinute = 1260 { didSet { invalidate() } }
    var duration = 60 { didSet { invalidate() } }
    var goal: TimingGoal = .openingOnly { didSet { invalidate() } }
    var run: TimingRun?
    var history: [TimingRun] = []
    var busy = false
    var message = ""
    var error = ""
    var exportFolder: URL?
    private var revision = 0
    private var task: Task<Void, Never>?
    private var loaded = false
    private let store: TimingStore
    init() {
        let testing =
            ProcessInfo.processInfo.arguments.contains("--timing-ui")
                || ProcessInfo.processInfo.arguments.contains("--timing-smoke")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(testing ? "C67VisitTiming-Tests" : "C67VisitTiming-v1")
        store = TimingStore(directory: base)
    }
    var venue: VenueFacts? { catalog?.venues.first { $0.id == venueID } }
    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            catalog = try TimingCatalog.load()
            let saved = try await store.history()
            history = saved.runs
            if saved.unreadable > 0 {
                message = "\(saved.unreadable) riwayat tidak terbaca; berkas dipertahankan."
            }
            if ProcessInfo.processInfo.arguments.contains("--timing-smoke") {
                goal = .lowerRain
                calculate(live: true)
            }
        } catch { self.error = error.localizedDescription }
    }
    func invalidate() {
        revision += 1
        task?.cancel()
        task = nil
        busy = false
        run = nil
        exportFolder = nil
    }
    func cancel() {
        invalidate()
        message = "Dibatalkan; hasil lama tidak diterapkan."
    }
    func stopPendingWork() { if busy { cancel() } }
    func calculate(live: Bool = false) {
        guard let catalog, let venue else { return }
        invalidate()
        let token = revision
        let request = TimingRequest(
            venueID: venueID, date: VenueClock.dateString(date),
            available: .init(startMinute, endMinute), durationMinutes: duration, goal: goal)
        busy = true
        error = ""
        message = live ? "Mencari pin MapKit dan prakiraan aktual…" : "Memeriksa fakta dan waktu…"
        task = Task {
            do {
                let started = Date()
                var environment: TimingEnvironment?
                var acquisitionError: String?
                if live {
                    do {
                        environment = try await LiveTimingEnvironment().fetch(venue: venue, date: request.date)
                    } catch is CancellationError { throw CancellationError() } catch {
                        acquisitionError = error.localizedDescription
                    }
                }
                try Task.checkCancellation()
                guard revision == token else { return }
                // UI fixtures retain their historical dates and use a matching authored clock.
                // Explicit provider requests and ordinary app launches keep the real clock.
                let fixtureClock = catalog.sources.map(\.checkedAt).max()?.addingTimeInterval(1) ?? Date.now
                let now = ProcessInfo.processInfo.arguments.contains("--timing-ui") && !live ? fixtureClock : Date.now
                var value = try VisitTimingEngine().evaluate(
                    request, catalog: catalog, environment: environment, now: now)
                if let acquisitionError {
                    value.warnings.append("Pengambilan konteks gagal: \(acquisitionError)")
                }
                value.elapsedSeconds = Date().timeIntervalSince(started)
                try Task.checkCancellation()
                guard revision == token else { return }
                try await store.save(value)
                let saved = try await store.history()
                guard revision == token, !Task.isCancelled else { return }
                run = value
                history = saved.runs
                busy = false
                message = "Selesai dalam \(String(format: "%.2f", value.elapsedSeconds)) detik."
                if ProcessInfo.processInfo.arguments.contains("--timing-smoke") {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                    let json = String(decoding: try encoder.encode(value), as: UTF8.self)
                    FileHandle.standardOutput.write(
                        Data(("VISIT_TIMING_BEGIN\n" + json + "\nVISIT_TIMING_END\n").utf8))
                }
            } catch is CancellationError {
                if revision == token { busy = false }
            } catch {
                if revision == token {
                    busy = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func preset(_ id: String) {
        goal = .openingOnly
        duration = 60
        startMinute = 420
        endMinute = 1260
        switch id {
        case "friday":
            venueID = "cikini"
            date = try! VenueClock.day("2026-11-06")
        case "weekend":
            venueID = "jatinegara"
            date = try! VenueClock.day("2026-11-08")
        case "unknown":
            venueID = "tanjung-duren"
            date = try! VenueClock.day("2026-11-08")
        case "suspended":
            venueID = "macan"
            date = try! VenueClock.day("2026-11-05")
        case "monday":
            venueID = "ragunan"
            date = try! VenueClock.day("2026-11-09")
        default:
            venueID = "gbk"
            date = try! VenueClock.day("2026-11-05")
        }
    }
    func export() async {
        guard let run else { return }
        do { exportFolder = try await store.export(run) } catch {
            self.error = error.localizedDescription
        }
    }
    func restore(_ value: TimingRun) {
        invalidate()
        venueID = value.request.venueID
        date = (try? VenueClock.day(value.request.date)) ?? Date()
        duration = value.request.durationMinutes
        startMinute = value.request.available.start
        endMinute = value.request.available.end
        goal = value.request.goal
        run = value
        message =
            "Hasil tersimpan \(VenueClock.dateString(value.createdAt)) \(VenueClock.label(value.createdAt)) WIB; hitung ulang untuk kondisi terbaru."
    }
}
