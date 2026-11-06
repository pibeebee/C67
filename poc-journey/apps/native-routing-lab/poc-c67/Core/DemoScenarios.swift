import Foundation

enum DemoScenario: String, CaseIterable, Identifiable {
    case start, regroup, stale, reviewed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .start: "Mulai pemeriksaan"
        case .regroup: "Satu peserta belum kembali"
        case .stale: "Lokasi tidak lagi baru"
        case .reviewed: "Pemeriksaan lengkap"
        }
    }
    var subtitle: String {
        switch self {
        case .start: "Empat peserta, semua belum diperiksa."
        case .regroup: "Dua diperiksa, satu tidak ikut, satu perlu ditindaklanjuti."
        case .stale: "Lokasi Ayu berumur tiga menit; status hadir tetap perlu diperiksa."
        case .reviewed: "Semua peserta sudah diperiksa oleh TL; lanjut ke review."
        }
    }
    var symbol: String {
        switch self { case .start: "list.bullet.clipboard"; case .regroup: "person.crop.circle.badge.questionmark"; case .stale: "clock.badge.exclamationmark"; case .reviewed: "checkmark.seal" }
    }
    func run(at now: Date = .now) throws -> RunState {
        var run = RunState(mode: .simulation)
        run.meetingPoint = MeetingPointSnapshot(latitude: -6.1754, longitude: 106.8272, radius: 100)
        run.sessions[0].name = "Kembali ke meeting point"
        let start = now.addingTimeInterval(1800)
        run.journeyPlan = JourneyPlan(runID: run.runID, activities: [
            TourActivity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!, title: "Kembali ke bus", start: start, end: start.addingTimeInterval(900), notes: "Berkumpul di Parkir B. Pemeriksaan oleh TL.", place: TourPlace(name: "Parkir B Monas", latitude: -6.1745, longitude: 106.828)),
            TourActivity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!, title: "Kunjungan museum", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200), place: TourPlace(name: "Museum Nasional", latitude: -6.1764, longitude: 106.8227)),
            TourActivity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!, title: "Waktu bebas", start: start.addingTimeInterval(8000), end: start.addingTimeInterval(11000))
        ], meetingPoint: run.meetingPoint, meetingName: "Meeting point demo")
        switch self {
        case .start: break
        case .regroup, .stale:
            try run.sessions[0].apply(.verify, participantID: "P02", at: now.addingTimeInterval(-70))
            try run.sessions[0].apply(.verify, participantID: "P03", at: now.addingTimeInterval(-40))
            if self == .regroup {
                try run.sessions[0].apply(.exclude, participantID: "P04", reason: "Tidak ikut perpindahan ini",
                                          arrangement: "Bertemu kembali di titik berikutnya sesuai catatan TL", at: now.addingTimeInterval(-20))
                try run.sessions[0].apply(.openFollowUp, participantID: "P01", reason: "Belum kembali ke meeting point; hubungi dan periksa langsung", at: now)
            }
        case .reviewed:
            for p in run.sessions[0].participants { try run.sessions[0].apply(.verify, participantID: p.id, at: now) }
        }
        return run
    }
}

enum ParticipantFilter: String, CaseIterable, Identifiable {
    case all = "Semua", unverified = "Belum diperiksa", followUp = "Tindak lanjut", verified = "Diperiksa", excluded = "Tidak ikut"
    var id: String { rawValue }
    func includes(_ p: Participant) -> Bool {
        switch self { case .all: true; case .unverified: p.expected && !p.verified; case .followUp: p.followUpOpen; case .verified: p.verified; case .excluded: !p.expected }
    }
    func results(in participants: [Participant], search: String) -> [Participant] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return participants.filter { includes($0) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) }
    }
}
