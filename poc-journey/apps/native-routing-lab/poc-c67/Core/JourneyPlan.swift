import Foundation

struct TourPlace: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 120
            && latitude.isFinite && longitude.isFinite && (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
    var meeting: MeetingPointSnapshot { MeetingPointSnapshot(latitude: latitude, longitude: longitude, radius: 100) }
}

struct TourActivity: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var timeZoneID = TimeZone.current.identifier
    var notes = ""
    var place: TourPlace?
    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 80 && notes.count <= 2000
            && start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite
            && start >= Date(timeIntervalSince1970: 0) && end < Date(timeIntervalSince1970: 32_503_680_000)
            && end > start && TimeZone(identifier: timeZoneID) != nil && (place == nil || place?.valid == true)
    }
    var calendarFingerprint: String {
        // Local receipt only; never sent to other participants or used as a Calendar event ID.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self).base64EncodedString()) ?? "invalid"
    }
    var timeLabel: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        return "\(formatter.string(from: start)) – \(formatter.string(from: end)) · \(timeZoneID)"
    }
}

struct JourneyPlan: Codable, Equatable {
    var schema = 1
    var runID: UUID
    var revision = 1
    var updatedAt = Date.now
    var activities: [TourActivity] = []
    var activeActivityID: UUID?
    var meetingPoint: MeetingPointSnapshot?
    var meetingName: String?
    var sortedActivities: [TourActivity] { activities.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start } }
    var activeActivity: TourActivity? { activities.first { $0.id == activeActivityID } }
    func validate(for run: UUID) throws {
        guard schema == 1, runID == run, revision > 0, revision < Int.max,
              updatedAt.timeIntervalSince1970.isFinite, updatedAt <= .now.addingTimeInterval(300),
              activities.count <= 50, Set(activities.map(\.id)).count == activities.count,
              activities.allSatisfy(\.valid), meetingPoint == nil || meetingPoint?.valid == true,
              (meetingName?.count ?? 0) <= 120 else { throw POCError.message("Data rundown tidak valid atau berasal dari perjalanan lain.") }
        guard try JSONEncoder().encode(self).count <= 200_000 else { throw POCError.message("Rundown terlalu besar. Kurangi catatan kegiatan.") }
        if let activeActivityID {
            guard let active = activities.first(where: { $0.id == activeActivityID }), let place = active.place,
                  meetingPoint == place.meeting, meetingName == place.name else { throw POCError.message("Titik kegiatan aktif tidak cocok.") }
        }
    }
}

struct CalendarExportReceipt: Codable, Equatable {
    var activityID: UUID
    var fingerprint: String
    var savedAt: Date
}

extension RunState {
    var effectivePlan: JourneyPlan { journeyPlan ?? JourneyPlan(runID: runID, updatedAt: Date(timeIntervalSince1970: 0), meetingPoint: meetingPoint, meetingName: meetingPoint == nil ? nil : "Meeting point") }
    mutating func editPlan(_ change: (inout JourneyPlan) throws -> Void) throws {
        guard joinedQR == nil else { throw POCError.message("Rundown peserta hanya dapat diperbarui oleh tour leader.") }
        var plan = effectivePlan
        try plan.validate(for: runID)
        try change(&plan)
        plan.revision += 1; plan.updatedAt = .now
        try plan.validate(for: runID)
        journeyPlan = plan; meetingPoint = plan.meetingPoint
    }
    mutating func saveActivity(_ activity: TourActivity) throws {
        guard activity.valid else { throw POCError.message("Isi judul, waktu selesai setelah mulai, dan lokasi yang valid.") }
        try editPlan { plan in
            if let index = plan.activities.firstIndex(where: { $0.id == activity.id }) { plan.activities[index] = activity }
            else { plan.activities.append(activity) }
            if plan.activeActivityID == activity.id {
                if let place = activity.place { plan.meetingPoint = place.meeting; plan.meetingName = place.name }
                else { plan.activeActivityID = nil; plan.meetingPoint = nil; plan.meetingName = nil }
            }
        }
    }
    mutating func deleteActivity(_ id: UUID) throws {
        try editPlan { plan in
            plan.activities.removeAll { $0.id == id }
            if plan.activeActivityID == id { plan.activeActivityID = nil; plan.meetingPoint = nil; plan.meetingName = nil }
        }
    }
    mutating func activateActivity(_ id: UUID) throws {
        try editPlan { plan in
            guard let activity = plan.activities.first(where: { $0.id == id }), let place = activity.place else { throw POCError.message("Tentukan lokasi kegiatan dahulu.") }
            plan.activeActivityID = id; plan.meetingPoint = place.meeting; plan.meetingName = place.name
        }
    }
    mutating func setMeetingPoint(_ point: MeetingPointSnapshot?, name: String?) throws {
        try editPlan { plan in
            plan.activeActivityID = nil; plan.meetingPoint = point; plan.meetingName = point == nil ? nil : name
        }
    }
    mutating func receivePlan(_ plan: JourneyPlan) throws {
        try plan.validate(for: runID)
        if let current = journeyPlan {
            guard plan.revision >= current.revision else { return }
            guard plan.revision != current.revision || plan == current else { throw POCError.message("Versi rundown bentrok. Periksa kembali dengan TL.") }
        }
        journeyPlan = plan; meetingPoint = plan.meetingPoint
    }
}
