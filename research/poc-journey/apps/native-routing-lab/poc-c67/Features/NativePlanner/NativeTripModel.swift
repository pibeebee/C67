import Foundation
import Observation
import WeatherKit

@MainActor @Observable final class NativeTripModel {
    var draft = NativeTripDraft.jakarta()
    let logs: NativeTripLogStore
    @ObservationIgnored private var activeOperationID: String?
    @ObservationIgnored private let localStore: NativeTripLocalStore
    @ObservationIgnored private var lastObservedDraft: NativeTripDraft?
    @ObservationIgnored private var calculating = false
    private(set) var localSession: NativeTripLocalSession?
    private(set) var storageNotice: String?
    private(set) var storageError: String?
    private(set) var storageBlocked = false
    var hasUnsavedDraft: Bool { localSession?.draft != draft }
    var hasSavedPlan: Bool { localSession?.acceptedReport != nil }
    var hasActiveTrip: Bool { localSession?.activeTrip?.isActive == true }
    var canAcceptReport: Bool {
        !hasActiveTrip && report?.fastest?.feasible == true && report?.draft == draft
    }
    func makeActiveController() -> NativeTripActiveController { .init(store: localStore, logs: logs) }
    func useActiveExample() {
        guard allowPlanningChanges() else { return }
        let example = NativeTripActiveSimulation.report()
        replaceDraft(example.draft)
        report = example
    }
    @discardableResult private func allowPlanningChanges() -> Bool {
        guard !hasActiveTrip else {
            storageError = "Selesaikan trip aktif sebelum mengganti rencana awal atau input tujuan."
            return false
        }
        return true
    }

    init(logs: NativeTripLogStore? = nil, localStore: NativeTripLocalStore? = nil) {
        self.logs = logs ?? .shared
        self.localStore = localStore ?? NativeTripLocalStore()
        self.logs.record("planner.opened", category: "app")
        restoreLocal()
    }
    private(set) var report: NativeTripReport?
    private(set) var isBusy = false
    private(set) var phase = ""
    private(set) var error: String?
    private(set) var matches: [String: [NativeTripMatch]] = [:]
    private(set) var lookupStates: [String: NativeTripLookupState] = [:]
    private(set) var searchAttempts: [NativeTripSearchAttempt] = []
    @ObservationIgnored private var lookupQueries: [String: String] = [:]
    private(set) var attribution: WeatherAttribution?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var services: NativeTripAppleServices?
    @ObservationIgnored private var generation = UUID()

    func restoreLocal() {
        cancel(reason: "restore")
        do {
            let loaded = try localStore.load()
            localSession = loaded.session
            storageBlocked = false
            storageError = nil
            storageNotice = loaded.notice
            if let session = loaded.session {
                replaceDraft(session.draft, allowActive: true)
                if let saved = session.acceptedReport, saved.draft == session.draft { report = saved }
                storageNotice =
                    loaded.notice
                        ?? "Rencana lokal dibuka. ETA dan cuaca merupakan data saat perhitungan sebelumnya."
                logs.record(
                    "trip.restored", category: "storage", fields: ["revision": String(session.revision)])
            }
            lastObservedDraft = draft
        } catch {
            storageBlocked = true
            storageError = error.localizedDescription
            logs.record("trip.restore_failed", category: "storage", level: "error")
        }
    }

    func saveLocal(acceptReport: Bool = false) {
        guard !storageBlocked, allowPlanningChanges() else { return }
        do {
            var value = localSession ?? NativeTripLocalSession(draft: draft)
            value.draft = draft
            if acceptReport {
                guard let report, report.draft == draft else {
                    throw NativeTripError.message(
                        "Input sudah berubah. Hitung kembali sebelum menyimpan itinerary.")
                }
                try NativeTripLocalSession.validateAccepted(report)
                value.acceptedReport = report
                value.activeTrip = nil
            }
            let saved = try localStore.commit(value, expected: localSession)
            localSession = saved
            storageError = nil
            storageNotice =
                acceptReport ? "Itinerary pilihan tersimpan di perangkat." : "Draft tersimpan di perangkat."
            logs.record(
                "trip.saved", category: "storage",
                fields: ["revision": String(saved.revision), "accepted": String(acceptReport)])
        } catch {
            storageNotice = nil
            storageError = error.localizedDescription
            logs.record("trip.save_failed", category: "storage", level: "error")
        }
    }

    func useStorageExample() {
        guard allowPlanningChanges() else { return }
        let example = NativeTripLocalSession.simulatedReport()
        replaceDraft(example.draft)
        report = example
    }

    func failNextLocalSave() {
        localStore.failNextWrite = true
        storageNotice = "Satu penyimpanan berikutnya akan digagalkan untuk pengujian."
    }

    var unresolvedCount: Int { draft.allPoints.filter { $0.coordinate == nil }.count }

    var pendingSearchCount: Int {
        draft.allPoints.filter {
            $0.coordinate == nil && !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && matches[$0.id]?.isEmpty != false
        }.count
    }

    func inputChanged() {
        guard lastObservedDraft != draft else { return }
        lastObservedDraft = draft
        storageNotice = nil
        if calculating { cancel(reason: "input_changed") }
        let activeIDs = Set(draft.allPoints.map(\.id))
        matches = matches.filter { activeIDs.contains($0.key) }
        lookupStates = lookupStates.filter { activeIDs.contains($0.key) }
        lookupQueries = lookupQueries.filter { activeIDs.contains($0.key) }
        for point in draft.allPoints {
            let key = "\(point.query)|\(draft.searchContext)|\(String(describing: point.searchRegion))"
            if let previous = lookupQueries[point.id], previous != key, point.coordinate == nil {
                matches[point.id] = nil
                lookupStates[point.id] = nil
            }
            lookupQueries[point.id] = key
        }
        report = nil
        attribution = nil
        if !isBusy {
            error = nil
            phase = ""
        }
    }

    func cancel(reason: String = "user") {
        let wasBusy = isBusy
        generation = UUID()
        job?.cancel()
        services?.cancel()
        job = nil
        calculating = false
        isBusy = false
        if wasBusy {
            logs.record(
                "operation.cancelled", category: "planner", operationID: activeOperationID,
                fields: ["reason": reason, "phase": phase])
            activeOperationID = nil
            phase = "Dibatalkan"
            for id in lookupStates.keys where lookupStates[id]?.kind == .searching {
                lookupStates[id] = .init(
                    kind: .deferred, detail: "Pencarian dibatalkan; lokasi belum diverifikasi.")
            }
        }
    }

    func importDraft(_ data: Data) throws {
        guard data.count <= 1_000_000 else {
            throw NativeTripError.message("File input terlalu besar.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(NativeTripDraft.self, from: data)
        try value.validate()
        replaceDraft(value)
    }

    func startNewTrip() { replaceDraft(.jakarta()) }

    func useJakartaExample() { replaceDraft(.jakartaFivePlaces()) }

    func adoptJakartaProfile() {
        guard allowPlanningChanges() else { return }
        var value = draft
        value.configureJakarta()
        replaceDraft(value)
        storageNotice =
            "Profil Jakarta dipilih. Koordinat dipertahankan; periksa semua pin sebelum menghitung. Simpan untuk mengganti data tersimpan."
    }

    func useExample() { replaceDraft(.japanExample()) }

    func appendPlaces(_ text: String) throws {
        guard allowPlanningChanges() else {
            throw NativeTripError.message("Trip aktif masih berlangsung.")
        }
        try draft.appendPlaces(text)
        logs.recordJSON("input.list_added", category: "input", value: draft)
        inputChanged()
    }

    private func replaceDraft(_ value: NativeTripDraft, allowActive: Bool = false) {
        guard allowActive || allowPlanningChanges() else { return }
        cancel()
        draft = value
        lastObservedDraft = value
        storageNotice = nil
        matches = [:]
        lookupStates = [:]
        searchAttempts = []
        lookupQueries = [:]
        report = nil
        error = nil
        attribution = nil
        phase = ""
        logs.recordJSON("input.replaced", category: "input", value: draft)
    }

    func saveStop(_ stop: NativeTripStop) {
        guard allowPlanningChanges() else { return }
        guard acceptsLocation(stop.point) else { return }
        guard let index = draft.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        draft.stops[index] = stop
        logs.recordJSON("input.stop_saved", category: "input", value: stop)
    }

    func removeStops(at offsets: IndexSet) {
        guard allowPlanningChanges() else { return }
        draft.stops = draft.stops.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        logs.recordJSON("input.stops_removed", category: "input", value: draft)
        inputChanged()
    }

    private func acceptsLocation(_ point: NativeTripPoint) -> Bool {
        guard draft.isJakartaProfile, point.coordinate != nil else { return true }
        guard NativeTripJakarta.contains(latitude: point.latitude!, longitude: point.longitude!) else {
            error =
                "Pin " + point.title + " di luar cakupan Jakarta. Pilih cabang atau titik yang sesuai."
            return false
        }
        return true
    }

    func select(_ point: NativeTripPoint) {
        guard allowPlanningChanges() else { return }
        guard acceptsLocation(point) else { return }
        if draft.origin.id == point.id {
            draft.origin = point
        } else if draft.end.id == point.id {
            draft.end = point
        } else if let index = draft.stops.firstIndex(where: { $0.id == point.id }) {
            draft.stops[index].point = point
        } else {
            draft.stops.append(.init(point: point))
        }
        logs.recordJSON(
            "input.point_updated", category: "input", operationID: activeOperationID, value: point)
        matches[point.id] = nil
        lookupStates[point.id] =
            point.coordinate == nil
                ? nil
                : .init(kind: .resolved, detail: point.resolvedName ?? "Lokasi dipilih")
        report = nil
    }

    func resolveMissing() {
        guard allowPlanningChanges() else { return }
        guard draft.isJakartaProfile else {
            error = "Pilih profil Jakarta sebelum mencari lokasi baru. Data lama tetap tersedia."
            return
        }
        cancel()
        error = nil
        report = nil
        isBusy = true
        let identity = generation
        let pending = draft.allPoints.filter {
            $0.coordinate == nil && !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && matches[$0.id]?.isEmpty != false
        }
        let snapshot = draft
        activeOperationID = identity.uuidString
        logs.recordJSON(
            "input.snapshot", category: "input", operationID: activeOperationID, value: snapshot)
        let provider = NativeTripAppleServices(logs: logs, operationID: identity.uuidString)
        services = provider
        logs.record(
            "lookup.started", category: "planner", operationID: activeOperationID,
            fields: ["pointCount": String(pending.count)])
        job = Task { [weak self] in
            var queryCache: [String: [NativeTripMatch]] = [:]
            do {
                let summary = try await NativeTripBulkLookup.run(pending, id: { $0.id }) { point in
                    guard let self, self.generation == identity else { throw CancellationError() }
                    self.phase = "Mencari: \(point.title)"
                    func lookup(_ query: String) async throws -> [NativeTripMatch] {
                        let key = "\(query):\(String(describing: point.searchRegion))"
                        if let saved = queryCache[key] { return saved }
                        let raw = try await provider.searchPlaces(
                            query,
                            region: snapshot.isJakartaProfile ? NativeTripJakarta.region : point.searchRegion)
                        let found =
                            snapshot.isJakartaProfile
                                ? raw.filter {
                                    NativeTripJakarta.contains(latitude: $0.latitude, longitude: $0.longitude)
                                }
                                : raw
                        queryCache[key] = found
                        return found
                    }
                    var result = try await lookup(snapshot.searchQuery(for: point))
                    // A different name helps only when the service actually returned no results, not on timeout.
                    if result.isEmpty, let alias = point.queryAliases?.first, alias != point.query {
                        result = try await lookup(snapshot.searchQuery(for: point, using: alias))
                    }
                    try Task.checkCancellation()
                    guard self.generation == identity else { throw CancellationError() }
                    self.searchAttempts = provider.searchAttempts
                    self.matches[point.id] = result
                    let chosen = NativeTripLocationSelection.automaticMatch(
                        result, point: point, context: snapshot.searchContext,
                        requireExactName: snapshot.isJakartaProfile)
                    if let chosen {
                        self.select(Self.applying(chosen, to: point))
                        return .init(kind: .resolved, detail: "Lokasi dipilih dari hasil MapKit.")
                    }
                    return .init(
                        kind: result.isEmpty ? .noResults : .needsSelection,
                        detail: result.isEmpty
                            ? "Pencarian belum menemukan hasil; coba nama alternatif atau pilih pin pada peta."
                            : "Pilih satu dari \(result.count) kandidat MapKit.")
                } update: { [weak self] id, state in
                    guard let self, self.generation == identity else { return }
                    self.lookupStates[id] = state
                    self.logs.record(
                        "lookup.point_state", category: "planner", operationID: identity.uuidString,
                        fields: ["pointID": id, "state": state.kind.rawValue, "detail": state.detail])
                }
                guard let self, self.generation == identity else { return }
                self.searchAttempts = provider.searchAttempts
                self.isBusy = false
                self.phase = "Pencarian selesai · \(self.unresolvedCount) titik belum dipilih"
                self.logs.record(
                    "lookup.completed", category: "planner", operationID: identity.uuidString,
                    fields: [
                        "attempted": String(summary.attempted), "failed": String(summary.failed),
                        "deferred": String(summary.deferred), "unresolved": String(self.unresolvedCount),
                    ])
                self.activeOperationID = nil
                if summary.failed > 0 {
                    self.error =
                        "\(summary.failed) pencarian belum berhasil, \(summary.deferred) ditunda. Buka detail tempat untuk mencoba kembali atau memilih pin. Lokasi yang sudah dipilih dipertahankan."
                }
            } catch {
                guard let self, self.generation == identity, !Task.isCancelled else { return }
                self.searchAttempts = provider.searchAttempts
                self.isBusy = false
                self.error = error.localizedDescription
                self.logs.record(
                    "lookup.failed", category: "planner", level: "error", operationID: identity.uuidString,
                    fields: NativeTripLogStore.errorFields(error))
                self.activeOperationID = nil
            }
        }
    }

    var searchDiagnostics: String {
        var lines = [
            "PoC C67 · native-search-v2-20261103",
            "Area adalah petunjuk pencarian, bukan lokasi yang sudah dikonfirmasi.",
            "Konteks area: \(draft.searchContext.isEmpty ? "tanpa konteks" : draft.searchContext)",
        ]
        for point in draft.allPoints {
            let state = lookupStates[point.id]
            lines.append(
                "\(point.id) · \(point.title): \(point.coordinate != nil ? "lokasi dipilih" : state?.kind.title ?? "belum dicari")"
            )
            if let state { lines.append(state.detail) }
        }
        for attempt in searchAttempts {
            lines.append(
                "Query: \(attempt.query) | area: \(attempt.region) | \(String(format: "%.1f", attempt.elapsed)) dtk | \(attempt.result) | \(attempt.diagnostic ?? "tanpa error")"
            )
        }
        return lines.joined(separator: "\n")
    }

    static func applying(_ match: NativeTripMatch, to point: NativeTripPoint) -> NativeTripPoint {
        var value = point
        value.latitude = match.latitude
        value.longitude = match.longitude
        value.resolvedName = match.name
        value.address = match.address
        value.selectionSource = "MapKit Local Search"
        return value
    }

    func calculate() {
        guard allowPlanningChanges() else { return }
        cancel()
        report = nil
        error = nil
        attribution = nil
        let snapshot = draft
        let identity = generation
        activeOperationID = identity.uuidString
        logs.recordJSON(
            "input.snapshot", category: "input", operationID: activeOperationID, value: snapshot)
        do {
            guard snapshot.isJakartaProfile else {
                throw NativeTripError.message(
                    "Pilih profil Jakarta dan mobil/taksi sebelum menghitung. Rencana lama tetap dapat dibuka."
                )
            }
            try snapshot.validate()
        } catch {
            self.error = error.localizedDescription
            logs.record(
                "plan.validation_failed", category: "planner", level: "warning",
                operationID: activeOperationID, fields: NativeTripLogStore.errorFields(error))
            activeOperationID = nil
            return
        }
        let provider = NativeTripAppleServices(
            logs: logs, operationID: identity.uuidString, requestLimit: snapshot.routingRequestLimit ?? 96
        )
        services = provider
        isBusy = true
        calculating = true
        phase = "Memulai perhitungan"
        logs.record("plan.started", category: "planner", operationID: activeOperationID)
        job = Task { [weak self] in
            do {
                var result = try await NativeTripEngine.plan(snapshot, services: provider) {
                    [weak self] value in
                    guard let self, self.generation == identity else { return }
                    self.phase = value
                    self.logs.record(
                        "plan.progress", category: "planner", operationID: identity.uuidString,
                        fields: ["phase": value])
                }
                try Task.checkCancellation()
                guard let self, self.generation == identity else { return }
                guard self.draft == snapshot else {
                    self.cancel(reason: "stale_input")
                    return
                }
                if let credit = provider.attribution {
                    result.storedWeatherCredit = .init(
                        serviceName: credit.serviceName, legalPageURL: credit.legalPageURL,
                        combinedMarkLightURL: credit.combinedMarkLightURL,
                        combinedMarkDarkURL: credit.combinedMarkDarkURL)
                }
                self.calculating = false
                self.report = result
                self.attribution = provider.attribution
                self.isBusy = false
                self.phase = result.status
                self.logs.record(
                    "plan.completed", category: "planner", operationID: identity.uuidString,
                    fields: [
                        "status": result.status, "requests": String(result.requests),
                        "report": result.textReport,
                    ])
                self.activeOperationID = nil
            } catch {
                guard let self, self.generation == identity, !Task.isCancelled else { return }
                self.isBusy = false
                self.error = error.localizedDescription
                self.logs.record(
                    "plan.failed", category: "planner", level: "error", operationID: identity.uuidString,
                    fields: NativeTripLogStore.errorFields(error))
                self.activeOperationID = nil
            }
        }
    }
}

extension NativeTripReport {
    var textReport: String {
        var lines = [
            "# Itinerary native PoC C67", status,
            "Berangkat: \(draft.clock(draft.departure)) (\(draft.timeZoneID))",
            draft.deadlineSummary, "AI: tidak digunakan",
            draft.isJakartaProfile
                ? "Jakarta · ETA mobil/taksi · cuaca Open-Meteo"
                : "MapKit transit: estimasi ETA, bukan jadwal atau detail jalur kereta.",
            optimizerNote ?? "Baseline geografis", "",
        ]
        for (index, stop) in draft.stops.enumerated() {
            lines.append(
                "Input \(index + 1): \(stop.point.title) · \(stop.dwell(defaultMinutes: draft.defaultDwell)) menit"
            )
            if stop.role == .visit {
                lines.append("   Jam operasional: \(stop.opening?.summary ?? "belum diisi")")
                if let opening = stop.opening {
                    lines.append(
                        "   Input manual · tanggal \(opening.serviceDate ?? NativeTripOpening.dateKey(draft.departure, timeZone: draft.timeZone)) · \(opening.timeZoneID ?? draft.timeZoneID)"
                    )
                    if let note = opening.sourceNote { lines.append("   Catatan sumber: \(note)") }
                }
            }
        }
        let displayed = fastest.map { [$0] } ?? candidates
        for candidate in displayed {
            lines.append("\nKandidat: \(candidate.id)")
            lines.append(
                "Lengkap: \(candidate.complete); layak terhadap batas yang diketahui: \(candidate.feasible)"
            )
            if candidate.complete {
                lines.append(
                    "Total durasi trip: \(String(format: "%.1f", candidate.elapsedMinutes)) menit. Perjalanan: \(String(format: "%.1f", candidate.travelMinutes)) menit; menunggu buka: \(String(format: "%.1f", candidate.waitingMinutes)) menit; singgah: \(candidate.dwellMinutes) menit."
                )
            } else {
                lines.append("Total durasi trip: belum diketahui; kandidat belum lengkap.")
            }
            for (index, leg) in candidate.legs.enumerated() {
                lines.append(
                    "\(index + 1). \(leg.from.title) → \(leg.to.title) | berangkat \(draft.clock(leg.departure)) | tiba \(leg.arrival.map(draft.clock) ?? "belum diketahui") | singgah \(leg.dwellMinutes) menit (\(leg.dwellSource))"
                )
                if let visit = leg.visit { lines.append("   Mulai singgah: \(draft.clock(visit))") }
                if let leave = leg.leave { lines.append("   Lanjut: \(draft.clock(leave))") }
                if let arrival = leg.arrival, let visit = leg.visit, visit > arrival {
                    lines.append(
                        "   Menunggu buka: \(String(format: "%.1f", visit.timeIntervalSince(arrival) / 60)) menit"
                    )
                }
                for option in leg.options {
                    lines.append(
                        "   \(option.mode.title): \(option.seconds.map { String(format: "%.1f menit", $0 / 60) } ?? "belum tersedia") [\(option.status)] · \(option.note)"
                    )
                }
            }
            lines.append(contentsOf: candidate.conflicts.map { "Konflik: \($0)" })
            lines.append(contentsOf: Set(candidate.uncertainties).sorted().map { "Bersyarat: \($0)" })
        }
        lines.append("\n\(weatherNote)")
        lines.append(
            contentsOf: forecasts.map {
                "Cuaca \($0.pointID): \($0.status) · sumber \($0.provider?.title ?? "belum tersedia") · \($0.note)"
            })
        if forecasts.contains(where: { $0.provider == .openMeteo }) {
            lines.append(NativeTripWeatherProvider.openMeteoCredit)
        }
        lines.append(
            "Pencarian terbatas: seed geografis dibandingkan menggunakan ETA aktual MapKit. Tidak menjamin optimum global."
        )
        lines.append(
            "Permintaan arah/ETA MapKit: \(requests). Laporan ini bukan bukti uji perangkat atau jaminan layanan transportasi."
        )
        return lines.joined(separator: "\n")
    }
}
