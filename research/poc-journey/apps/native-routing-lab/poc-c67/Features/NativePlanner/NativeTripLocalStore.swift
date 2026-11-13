import Foundation

/// A persisted plan is an explicit choice, independent of the draft currently being edited.
struct NativeTripLocalSession: Codable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var revision = 0
    var savedAt = Date()
    var draft: NativeTripDraft
    var acceptedReport: NativeTripReport?
    var activeTrip: NativeTripActiveTrip? = nil

    func validate() throws {
        guard schemaVersion == 1 && activeTrip == nil || schemaVersion == 2 && activeTrip != nil,
              revision > 0, savedAt.timeIntervalSince1970.isFinite,
              TimeZone(identifier: draft.timeZoneID) != nil, draft.stops.count <= 20,
              Set(draft.stops.map(\.id)).count == draft.stops.count
        else { throw NativeTripError.message("Snapshot lokal tidak valid.") }
        if let report = acceptedReport { try Self.validateAccepted(report) }
        if let activeTrip {
            guard let acceptedReport else {
                throw NativeTripError.message("Trip aktif memerlukan rencana awal tersimpan.")
            }
            try activeTrip.validate(original: acceptedReport)
        }
    }

    static func validateAccepted(_ report: NativeTripReport, allowNoStops: Bool = false) throws {
        try report.draft.validate(allowNoStops: allowNoStops)
        let draft = report.draft
        guard let candidate = report.fastest, candidate.feasible,
              Set(candidate.order) == Set(draft.stops.map(\.id)),
              candidate.order.count == draft.stops.count,
              candidate.legs.count == candidate.order.count + 1,
              candidate.finish != nil, report.generatedAt.timeIntervalSince1970.isFinite
        else {
            throw NativeTripError.message(
                "Hanya itinerary lengkap tanpa konflik yang dapat disimpan sebagai pilihan.")
        }
        let stops = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
        var from = draft.origin
        var cursor = draft.departure
        var travel = 0.0
        var waiting = 0.0
        var dwell = 0
        for (index, leg) in candidate.legs.enumerated() {
            let isEnd = index == candidate.order.count
            let stop = isEnd ? nil : stops[candidate.order[index]]
            let target = isEnd ? draft.endPoint : stop!.point
            let minutes = stop?.dwell(defaultMinutes: draft.defaultDwell) ?? 0
            guard leg.from == from, leg.to == target, leg.isReturn == isEnd,
                  leg.dwellMinutes == minutes, let eta = leg.chosen, eta.usable,
                  draft.modes.contains(eta.mode), let seconds = eta.seconds,
                  Self.near(leg.departure, cursor)
            else { throw NativeTripError.message("Ruas itinerary tersimpan tidak konsisten.") }
            if eta.mode == .walking, seconds > Double(draft.maximumWalkingMinutes) * 60 {
                throw NativeTripError.message("Ruas berjalan melewati batas pengguna.")
            }
            let arrival = cursor.addingTimeInterval(seconds)
            var visit = arrival
            if stop?.role == .visit {
                if let opens = stop?.opening?.opensMinute {
                    visit = max(visit, draft.clockDate(minutes: opens))
                }
            }
            let leave = visit.addingTimeInterval(Double(minutes) * 60)
            guard Self.near(leg.arrival, arrival), Self.near(leg.visit, visit),
                  Self.near(leg.leave, leave),
                  leave <= draft.deadline,
                  stop?.role != .visit
                  || stop?.opening?.closesMinute.map({ leave <= draft.clockDate(minutes: $0) }) != false
            else {
                throw NativeTripError.message(
                    "Waktu itinerary tersimpan tidak memenuhi batas yang diketahui.")
            }
            travel += seconds / 60
            waiting += visit.timeIntervalSince(arrival) / 60
            dwell += minutes
            from = target
            cursor = leave
        }
        guard Self.near(candidate.finish, cursor), abs(candidate.travelMinutes - travel) < 0.01,
              abs(candidate.waitingMinutes - waiting) < 0.01, candidate.dwellMinutes == dwell,
              candidate.elapsedMinutes.isFinite,
              abs(candidate.elapsedMinutes * 60 - cursor.timeIntervalSince(draft.departure)) < 1
        else {
            throw NativeTripError.message("Penjumlahan durasi itinerary tersimpan tidak konsisten.")
        }
        if draft.usesPrivateCar {
            let modes = candidate.legs.compactMap { $0.chosen?.mode }
            guard modes.allSatisfy({ $0 == .automobile }) || modes.allSatisfy({ $0 != .automobile })
            else {
                throw NativeTripError.message("Strategi mobil pribadi tersimpan tidak konsisten.")
            }
        }
        if report.forecasts.contains(where: { $0.provider == .weatherKit }),
           report.storedWeatherCredit == nil
        {
            throw NativeTripError.message("Atribusi Apple Weather belum tersedia untuk disimpan.")
        }
    }

    private static func near(_ actual: Date?, _ expected: Date) -> Bool {
        actual.map { abs($0.timeIntervalSince(expected)) < 1 } == true
    }
}

struct NativeTripLocalLoad {
    var session: NativeTripLocalSession?
    var notice: String?
}

enum NativeTripLocalStoreError: LocalizedError {
    case futureVersion
    case unreadable
    case changed
    var errorDescription: String? {
        switch self {
        case .futureVersion:
            "Data dibuat oleh versi aplikasi yang lebih baru. Penyimpanan dilindungi agar data tidak tertimpa."
        case .unreadable:
            "Data lokal tidak dapat dibaca. Berkas dipertahankan; coba buka lagi setelah memeriksa penyimpanan."
        case .changed: "Rencana tersimpan sudah berubah. Buka kembali sebelum menyimpan perubahan ini."
        }
    }
}

/// Serial app-owned access. The primary snapshot is the atomic commit point.
/// No network, auth, Apple service object, or logging success is needed for a commit.
@MainActor final class NativeTripLocalStore {
    let directory: URL
    var failNextWrite = false
    private let manager = FileManager.default
    var primaryURL: URL { directory.appendingPathComponent("trip-v1.json") }
    var backupURL: URL { directory.appendingPathComponent("trip-v1.backup.json") }

    init(directory: URL? = nil) {
        self.directory =
            directory
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(
                    ProcessInfo.processInfo.arguments.contains("--jakarta-ui-testing")
                        ? "NativeTripJakartaUITests"
                        : ProcessInfo.processInfo.arguments.contains("--active-ui-testing")
                        ? "NativeTripActiveUITests" : "NativeTripPlans", isDirectory: true)
    }

    func load() throws -> NativeTripLocalLoad {
        let primaryExists = manager.fileExists(atPath: primaryURL.path)
        let backupExists = manager.fileExists(atPath: backupURL.path)
        if !primaryExists && !backupExists { return .init() }
        if primaryExists {
            do { return .init(session: try decode(primaryURL)) } catch NativeTripLocalStoreError
                .futureVersion
            { throw NativeTripLocalStoreError.futureVersion } catch {}
        }
        // Recover only a validated backup. Preserve unreadable files when recovery fails.
        if backupExists {
            do {
                return .init(
                    session: try decode(backupURL),
                    notice:
                    "Rencana dipulihkan dari salinan terakhir yang valid. Perubahan terakhir mungkin belum tersedia; periksa sebelum menyimpan."
                )
            } catch NativeTripLocalStoreError.futureVersion {
                throw NativeTripLocalStoreError.futureVersion
            } catch {}
        }
        throw NativeTripLocalStoreError.unreadable
    }

    func commit(_ proposed: NativeTripLocalSession, expected: NativeTripLocalSession?) throws
        -> NativeTripLocalSession
    {
        let current = try load().session
        guard current?.id == expected?.id, current?.revision == expected?.revision else {
            throw NativeTripLocalStoreError.changed
        }
        var value = proposed
        value.schemaVersion = value.activeTrip == nil ? 1 : 2
        value.revision = (current?.revision ?? 0) + 1
        value.savedAt = Date()
        try value.validate()
        let data = try Self.encoder().encode(value)
        guard data.count <= 8_000_000 else {
            throw NativeTripError.message("Rencana lokal terlalu besar untuk PoC.")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if failNextWrite {
            failNextWrite = false
            throw NativeTripError.message(
                "Simulasi kegagalan simpan lokal. Data tersimpan sebelumnya tetap tersedia.")
        }
        // Back up the validated current value, never corrupt bytes from the primary file.
        if let current { try Self.encoder().encode(current).write(to: backupURL, options: .atomic) }
        try data.write(to: primaryURL, options: .atomic)
        return value
    }

    private func decode(_ url: URL) throws -> NativeTripLocalSession {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_000_000 else { throw NativeTripLocalStoreError.unreadable }
        let data = try Data(contentsOf: url)
        struct Header: Decodable { var schemaVersion: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        if version > 2 { throw NativeTripLocalStoreError.futureVersion }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(NativeTripLocalSession.self, from: data)
        try value.validate()
        return value
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension NativeTripLocalSession {
    /// Explicit diagnostics example; never used as a fallback for a live provider.
    static func simulatedReport() -> NativeTripReport {
        let date = ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z")!
        let origin = NativeTripPoint(
            id: "sim-origin", title: "Awal simulasi", query: "", latitude: 0, longitude: 0,
            selectionSource: "Simulasi lokal")
        let stops = (1 ... 4).map { index in
            NativeTripStop(
                point: .init(
                    id: "sim-\(index)", title: "Tujuan simulasi \(index)", query: "", latitude: 0,
                    longitude: Double(index) * 0.001, selectionSource: "Simulasi lokal"))
        }
        var draft = NativeTripDraft(
            departure: date, timeZoneID: "Asia/Jakarta", origin: origin, end: origin, stops: stops,
            walking: true, transit: false)
        draft.finishBy = date.addingTimeInterval(5 * 3600)
        var candidate = NativeTripCandidate(id: "simulated", order: stops.map(\.id))
        var from = origin
        var cursor = date
        for (index, stop) in (stops + [NativeTripStop(point: origin, role: .transfer)]).enumerated() {
            let eta = NativeTripETA(
                id: "sim-eta-\(index)", mode: .walking, seconds: 600, status: "available",
                note: "ETA sintetis 10 menit; bukan data MapKit.")
            let arrival = cursor.addingTimeInterval(600)
            let dwell = stop.dwell(defaultMinutes: 30)
            let leave = arrival.addingTimeInterval(Double(dwell) * 60)
            candidate.legs.append(
                .init(
                    id: "sim-leg-\(index)", from: from, to: stop.point, departure: cursor, arrival: arrival,
                    visit: arrival, leave: leave, dwellMinutes: dwell, dwellSource: "simulasi",
                    isReturn: index == stops.count, chosen: eta, options: [eta],
                    notes: ["Data simulasi lokal."]))
            candidate.travelMinutes += 10
            candidate.dwellMinutes += dwell
            from = stop.point
            cursor = leave
        }
        candidate.finish = cursor
        candidate.complete = true
        candidate.uncertainties = ["Semua lokasi dan ETA sintetis; jam operasional belum diketahui."]
        return .init(
            draft: draft, candidates: [candidate], fastest: candidate, forecasts: [], requests: 0,
            weatherNote: "Simulasi lokal tanpa cuaca atau request jaringan.",
            optimizerNote: "Contoh penyimpanan sintetis; bukan hasil optimizer atau provider live.")
    }
}
