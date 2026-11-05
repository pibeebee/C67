import Foundation
import Observation
import WeatherKit

@MainActor @Observable final class NativeTripActiveController {
    typealias Planner =
        @MainActor (NativeTripReplanProjection, @escaping (String) -> Void) async throws ->
        NativeTripReport
    private(set) var session: NativeTripLocalSession?
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var phase = ""
    private(set) var isBusy = false
    let runtimeSessionID = UUID()
    @ObservationIgnored private let store: NativeTripLocalStore
    @ObservationIgnored private let logs: NativeTripLogStore
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let injectedPlanner: Planner?
    @ObservationIgnored private let timeoutSeconds: Double
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var services: NativeTripAppleServices?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var retryAction: (NativeTripActiveCommand, String, Date)?

    init(
        store: NativeTripLocalStore, logs: NativeTripLogStore,
        clock: @escaping @MainActor () -> Date = { Date() }, timeoutSeconds: Double = 300,
        planner: Planner? = nil
    ) {
        self.store = store
        self.logs = logs
        self.clock = clock
        self.timeoutSeconds = max(0.001, timeoutSeconds)
        self.injectedPlanner = planner
        reload()
    }

    var active: NativeTripActiveTrip? { session?.activeTrip }
    var original: NativeTripReport? { session?.acceptedReport }
    var now: Date { active?.simulationNow ?? clock() }
    var canRetry: Bool { retryAction != nil }
    var canApply: Bool {
        guard let active, let proposal = active.proposal else { return false }
        return proposal.canApply && proposal.producerSessionID == runtimeSessionID
            && proposal.projection.baseRevision == active.inputRevision
            && now >= proposal.projection.asOf
            && now.timeIntervalSince(proposal.projection.draft.departure) <= 60
    }
    var anchorTitle: String {
        guard let active, let original else { return "Titik awal" }
        let current =
            active.current?.stopID
                ?? active.lastCompleted?.stopID
        return original.draft.stops.first { $0.id == current }?.point.title
            ?? original.draft.origin.title
    }

    func reload() {
        cancel(reason: "reload")
        do {
            let result = try store.load()
            session = result.session
            notice = result.notice
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func start() {
        do {
            guard var value = session, let report = value.acceptedReport, value.activeTrip == nil else {
                throw NativeTripError.message(
                    "Simpan itinerary pilihan terlebih dahulu. Trip yang sudah dimulai tidak dapat dimulai ulang."
                )
            }
            guard report.simulationKind != nil || report.draft.isJakartaProfile else {
                throw NativeTripError.message(
                    "Itinerary lama tetap tersedia. Hitung dan simpan itinerary profil Jakarta sebelum memulai trip baru."
                )
            }
            let time = report.simulationKind == "active" ? report.draft.departure : clock()
            value.activeTrip = try NativeTripActiveTrip.start(report: report, at: time)
            session = try store.commit(value, expected: session)
            error = nil
            notice = "Trip dimulai dan tersimpan. Kedatangan dicatat manual."
            logs.record("trip.started", category: "active")
        } catch { self.error = error.localizedDescription }
    }

    func perform(
        _ command: NativeTripActiveCommand, actionID: String = UUID().uuidString, at time: Date? = nil
    ) {
        cancel(reason: "input_changed")
        let at = time ?? now
        do {
            guard var value = session, var active = value.activeTrip, let original = value.acceptedReport
            else {
                throw NativeTripError.message("Mulai trip terlebih dahulu.")
            }
            let oldRevision = active.inputRevision
            try active.perform(
                command, actionID: actionID, at: at, original: original, runtimeSessionID: runtimeSessionID)
            if active.inputRevision == oldRevision { return }
            value.activeTrip = active
            session = try store.commit(value, expected: session)
            retryAction = nil
            phase = ""
            error = nil
            notice = "Perubahan tersimpan di perangkat."
            logs.record(
                command.event, category: "active",
                fields: ["actionID": actionID, "revision": String(active.inputRevision)])
        } catch {
            self.error = error.localizedDescription
            notice = nil
            retryAction = (command, actionID, at)
            logs.record("trip.active_change_failed", category: "active", level: "error")
        }
    }

    func retry() {
        guard let (command, id, time) = retryAction else { return }
        if case .apply = command {
            perform(command, actionID: id)
        } else {
            perform(command, actionID: id, at: time)
        }
    }

    func failNextSave() {
        store.failNextWrite = true
        notice = "Satu penyimpanan berikutnya akan digagalkan untuk pengujian."
    }

    func cancel(reason: String = "user") {
        generation = UUID()
        job?.cancel()
        watchdog?.cancel()
        services?.cancel()
        job = nil
        watchdog = nil
        services = nil
        if isBusy {
            logs.record("replan.cancelled", category: "active", fields: ["reason": reason])
            phase = "Dibatalkan"
        }
        isBusy = false
    }

    func requestReplan(anchorConfirmed: Bool) {
        cancel(reason: "new_request")
        do {
            guard let active, let original else {
                throw NativeTripError.message("Mulai trip terlebih dahulu.")
            }
            guard original.simulationKind != nil || original.draft.isJakartaProfile else {
                throw NativeTripError.message(
                    "Fakta trip lama tetap tersimpan. Replan live sekarang memerlukan itinerary profil Jakarta; input tidak diganti otomatis."
                )
            }
            let projection = try active.projection(
                original: original, at: now, anchorConfirmed: anchorConfirmed)
            let token = generation
            let provider = NativeTripAppleServices(
                logs: logs, operationID: projection.requestID.uuidString,
                requestLimit: projection.draft.routingRequestLimit ?? 96,
                simulated: active.simulationNow != nil)
            services = provider
            isBusy = true
            error = nil
            notice = nil
            phase = "Menghitung sisa perjalanan"
            logs.record(
                "replan.started", category: "active",
                fields: [
                    "requestID": projection.requestID.uuidString, "revision": String(projection.baseRevision),
                ])
            let injected = injectedPlanner
            job = Task { [weak self] in
                do {
                    let progress: (String) -> Void = { [weak self] value in
                        guard let self, self.generation == token else { return }
                        self.phase = value
                    }
                    var report: NativeTripReport
                    if let injected {
                        report = try await injected(projection, progress)
                    } else {
                        report = try await NativeTripActivePlanner.plan(
                            projection, services: provider, progress: progress)
                    }
                    if let attribution = provider.attribution {
                        report.storedWeatherCredit = .init(
                            serviceName: attribution.serviceName, legalPageURL: attribution.legalPageURL,
                            combinedMarkLightURL: attribution.combinedMarkLightURL,
                            combinedMarkDarkURL: attribution.combinedMarkDarkURL)
                    }
                    guard let self else { return }
                    guard self.generation == token, !Task.isCancelled,
                          self.active?.inputRevision == projection.baseRevision
                    else {
                        self.logs.record("replan.stale_discarded", category: "active")
                        return
                    }
                    guard report.draft == projection.draft else {
                        throw NativeTripError.message("Hasil perhitungan tidak cocok dengan input sisa trip.")
                    }
                    if active.simulationNow != nil { report.simulationKind = "active" }
                    let proposal = NativeTripReplanProposal(
                        producerSessionID: self.runtimeSessionID, projection: projection,
                        report: report, baseline: report.candidates.first)
                    var value = self.session!
                    value.activeTrip!.proposal = proposal
                    self.session = try self.store.commit(value, expected: self.session)
                    self.watchdog?.cancel()
                    self.watchdog = nil
                    self.job = nil
                    self.services = nil
                    self.isBusy = false
                    self.phase =
                        proposal.canApply ? "Usulan siap ditinjau" : "Ada konflik atau data belum lengkap"
                    self.logs.record(
                        "replan.completed", category: "active",
                        fields: [
                            "requestID": projection.requestID.uuidString, "requests": String(report.requests),
                            "canApply": String(proposal.canApply),
                        ])
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.watchdog?.cancel()
                    self.watchdog = nil
                    self.job = nil
                    self.services = nil
                    self.isBusy = false
                    self.error = error.localizedDescription
                    self.phase = "Perhitungan belum berhasil"
                    self.logs.record("replan.failed", category: "active", level: "error")
                }
            }
            let timeout = timeoutSeconds
            watchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                guard let self, self.generation == token, self.isBusy else { return }
                self.cancel(reason: "timeout")
                self.error =
                    "Batas waktu perhitungan tercapai. Fakta dan rencana sebelumnya tetap tersimpan."
            }
        } catch {
            self.error = error.localizedDescription
            phase = "Periksa perubahan perjalanan"
        }
    }

    var textReport: String {
        guard let active, let original else { return "Belum ada trip aktif." }
        var lines = [
            "Trip aktif native PoC",
            active.simulationNow == nil
                ? "Waktu aktual, laporan manual" : "SIMULASI LOKAL · bukan perjalanan nyata",
            "Mulai: \(original.draft.clock(active.startedAt))",
            "Batas tiba: \(original.draft.clock(active.finishBy))",
            "Perlu hitung ulang: \(active.needsReplan)",
        ]
        for visit in active.visits {
            let title = original.draft.stops.first { $0.id == visit.stopID }?.point.title ?? visit.stopID
            lines.append(
                "\(title): \(visit.status.title); tiba \(visit.arrivedAt.map(original.draft.clock) ?? "unknown"); mulai \(visit.startedAt.map(original.draft.clock) ?? "unknown"); selesai \(visit.departedAt.map(original.draft.clock) ?? "unknown")"
            )
        }
        if let proposal = active.proposal {
            lines.append(
                "Usulan revisi \(proposal.projection.baseRevision); baseline selesai \(proposal.baseline?.finish.map(original.draft.clock) ?? "unknown"); kandidat selesai \(proposal.report.fastest?.finish.map(original.draft.clock) ?? "unknown")"
            )
            lines.append(contentsOf: proposal.projection.currentConflicts)
            lines.append(contentsOf: Array(Set(proposal.report.candidates.flatMap(\.conflicts))).sorted())
        }
        lines.append(contentsOf: active.warnings(original: original))
        return lines.joined(separator: "\n")
    }
}
