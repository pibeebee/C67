import Foundation

enum POCError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum RunMode: String, Codable, CaseIterable { case real = "Perangkat nyata", simulation = "Simulasi" }

struct AuditEvent: Codable, Identifiable {
    var id: UUID
    var at: Date
    var text: String
}

struct Participant: Codable, Identifiable {
    var id: String
    var name: String
    var expected = true
    var exclusionReason = ""
    var arrangement = ""
    var verifiedAt: Date?
    var followUp = ""
    var followUpOpen = false
    var followUpOutcome = ""
    var verified: Bool { expected && verifiedAt != nil }
    var displayID: String { UUID(uuidString: id) == nil ? id : String(id.prefix(6)) }
    static var fixture: [Participant] {
        [Participant(id: "P01", name: "Ayu"), Participant(id: "P02", name: "Budi"),
         Participant(id: "P03", name: "Ayu"), Participant(id: "P04", name: "Citra")]
    }
}

struct SessionCounts: Equatable {
    var total: Int; var expected: Int; var verified: Int; var unresolved: Int; var excluded: Int; var openCases: Int
    var canCloseNormally: Bool { expected > 0 && unresolved == 0 && openCases == 0 }
    var summary: String { "E \(expected) · V \(verified) · U \(unresolved) · X \(excluded) · O \(openCases)" }
}

struct AttendanceSession: Codable, Identifiable {
    var id = UUID()
    var name: String
    var participants = Participant.fixture
    var events: [AuditEvent] = []
    var closedAt: Date?
    var closureNote: String?
    var closedSummary: String?
    var counts: SessionCounts {
        let e = participants.filter(\.expected).count
        let v = participants.filter(\.verified).count
        return SessionCounts(total: participants.count, expected: e, verified: v, unresolved: e - v,
                             excluded: participants.count - e, openCases: participants.filter(\.followUpOpen).count)
    }
    mutating func apply(_ action: AttendanceAction, participantID: String? = nil,
                        reason: String = "", arrangement: String = "", actionID: UUID = UUID(), at: Date = .now) throws {
        if events.contains(where: { $0.id == actionID }) { return }
        guard closedAt == nil else { throw POCError.message("Sesi ditutup dan hanya dapat dibaca.") }
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrangement = arrangement.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .close || action == .closeWithNote {
            if action == .close && !counts.canCloseNormally { throw POCError.message("Masih ada peserta/kasus belum selesai. Gunakan Tutup dengan catatan.") }
            if action == .closeWithNote && reason.isEmpty { throw POCError.message("Alasan penutupan wajib diisi.") }
            closedSummary = counts.summary
            closedAt = at
            closureNote = action == .closeWithNote ? reason : nil
            events.append(AuditEvent(id: actionID, at: at, text: "Tutup pemeriksaan: \(counts.summary). \(reason)"))
            return
        }
        guard let index = participants.firstIndex(where: { $0.id == participantID }) else { throw POCError.message("Peserta tidak ditemukan.") }
        var p = participants[index]
        let old = "expected=\(p.expected), verified=\(p.verified), followUp=\(p.followUpOpen)"
        switch action {
        case .verify:
            guard p.expected else { throw POCError.message("Kembalikan ke Diharapkan sebelum pemeriksaan.") }
            if p.verified { return }
            p.verifiedAt = at
        case .undoVerification:
            guard !reason.isEmpty else { throw POCError.message("Alasan pembatalan wajib diisi.") }
            p.verifiedAt = nil
        case .exclude:
            guard !reason.isEmpty && !arrangement.isEmpty else { throw POCError.message("Alasan dan pengaturan tidak ikut wajib diisi.") }
            p.expected = false; p.exclusionReason = reason; p.arrangement = arrangement
        case .include:
            if p.expected { return }
            p.expected = true; p.verifiedAt = nil; p.exclusionReason = ""; p.arrangement = ""
        case .openFollowUp:
            if p.followUpOpen { return }
            guard !reason.isEmpty else { throw POCError.message("Konteks tindak lanjut wajib diisi.") }
            p.followUpOpen = true; p.followUp = reason; p.followUpOutcome = ""
        case .resolveFollowUp:
            guard p.followUpOpen && !reason.isEmpty else { throw POCError.message("Kasus aktif dan hasil tindak lanjut wajib ada.") }
            p.followUpOpen = false; p.followUpOutcome = reason
        case .close, .closeWithNote: break
        }
        participants[index] = p
        events.append(AuditEvent(id: actionID, at: at,
                                 text: "\(p.id) · \(action.rawValue) · \(old) → expected=\(p.expected), verified=\(p.verified), followUp=\(p.followUpOpen). \(reason) \(arrangement)"))
    }
}

enum AttendanceAction: String {
    case verify = "Diperiksa TL", undoVerification = "Batalkan pemeriksaan", exclude = "Tidak ikut", include = "Kembali ikut"
    case openFollowUp = "Buka tindak lanjut", resolveFollowUp = "Selesaikan tindak lanjut"
    case close = "Tutup pemeriksaan", closeWithNote = "Tutup dengan catatan"
}

struct CloudReference: Codable, Equatable {
    var runID: UUID
    var participantID: String
    var zoneName: String
    var ownerName: String
    var rootName: String
    var shareName: String
    var latestName: String
}

struct RunState: Codable {
    var runID = UUID()
    var mode: RunMode = .real
    var sessions = [AttendanceSession(name: "Pemeriksaan 1")]
    var meetingLatitude: Double?
    var meetingLongitude: Double?
    var meetingRadius = 100.0
    // Keep the existing JSON keys so previously saved meeting points still load.
    var meetingPoint: MeetingPointSnapshot? {
        get {
            guard let latitude = meetingLatitude, let longitude = meetingLongitude else { return nil }
            let point = MeetingPointSnapshot(latitude: latitude, longitude: longitude, radius: meetingRadius)
            return point.valid ? point : nil
        }
        set {
            meetingLatitude = newValue?.latitude; meetingLongitude = newValue?.longitude
            if let newValue { meetingRadius = newValue.radius }
        }
    }
    var owner: CloudReference?
    var binding: CloudReference?
    var qrMembers: [PairedMember]?
    var qrJourneyName: String?
    var qrLeaderName: String?
    var joinedQR: JoinedJourney?
    var leaderShares: [LeaderShare]?
    var leaderBinding: CloudReference?
    var journeyPlan: JourneyPlan?
    var calendarExports: [CalendarExportReceipt]?
    var ended = false
    var activeIndex: Int? { sessions.indices.last(where: { sessions[$0].closedAt == nil }) }
    mutating func nextSession() throws {
        guard !ended, activeIndex == nil else { throw POCError.message("Tutup sesi aktif terlebih dahulu; run juga harus masih aktif.") }
        var session = AttendanceSession(name: "Pemeriksaan \(sessions.count + 1)")
        if qrMembers != nil { session.participants = sessions.last!.participants.map { Participant(id: $0.id, name: $0.name) } }
        sessions.append(session)
    }
}

struct LocationSample: Codable, Equatable {
    var runID: UUID
    var epoch: UUID
    var sequence: Int
    var latitude: Double
    var longitude: Double
    var measuredAt: Date
    var accuracy: Double
    var reduced: Bool
    var simulated: Bool
    var valid: Bool {
        latitude.isFinite && longitude.isFinite && (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
            && accuracy.isFinite && (0 ... 40_075_000).contains(accuracy) && sequence > 0
            && (-62_135_596_800 ... 253_402_300_799).contains(measuredAt.timeIntervalSince1970)
    }
}

enum LocationRules {
    static let staleAfter: TimeInterval = 60
    static func freshness(_ sample: LocationSample?, now: Date = .now) -> String {
        guard let sample else { return "Belum ada data" }
        guard sample.valid else { return "Data lokasi tidak valid" }
        let age = now.timeIntervalSince(sample.measuredAt)
        if age < -5 { return "Waktu tidak dapat dinilai — periksa jam perangkat" }
        if age > staleAfter { return "Kedaluwarsa · \(Int(age)) dtk" }
        return "Lokasi terakhir · \(Int(max(0, age))) dtk"
    }
    static func canReplace(_ new: LocationSample, old: LocationSample?, runID: UUID, epoch: UUID, now: Date = .now) -> Bool {
        guard new.valid, new.runID == runID, new.epoch == epoch, !new.simulated,
              new.measuredAt <= now.addingTimeInterval(5) else { return false }
        guard let old else { return true }
        return old.epoch == new.epoch && new.sequence > old.sequence && new.measuredAt > old.measuredAt
    }
    static func mayUpload(_ sample: LocationSample, activeEpoch: UUID?, runID: UUID, expiresAt: Date?, now: Date = .now) -> Bool {
        guard let expiresAt, now < expiresAt, sample.epoch == activeEpoch, sample.runID == runID,
              sample.valid, !sample.simulated else { return false }
        let age = now.timeIntervalSince(sample.measuredAt)
        return age >= -5 && age <= staleAfter
    }
    static func proximity(distance: Double, radius: Double, sample: LocationSample, now: Date = .now) -> String {
        guard sample.valid, !sample.reduced, now.timeIntervalSince(sample.measuredAt) <= staleAfter,
              sample.measuredAt <= now.addingTimeInterval(5) else { return "Kedekatan tidak dapat dinilai" }
        if distance + sample.accuracy <= radius { return "Indikasi dekat — bukan bukti hadir" }
        if distance - sample.accuracy > radius { return "Indikasi jauh — tinjau manual" }
        return "Kedekatan tidak pasti"
    }
}
