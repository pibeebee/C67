import Foundation

enum NativeTripVisitStatus: String, Codable, Sendable {
    case pending, arrived, visiting, completed, skipped
    var title: String {
        switch self {
        case .pending: "Belum dikunjungi"
        case .arrived: "Sudah tiba · belum mulai kunjungan"
        case .visiting: "Sedang dikunjungi"
        case .completed: "Selesai dikunjungi"
        case .skipped: "Dilewati pengguna"
        }
    }
}

struct NativeTripVisitState: Codable, Sendable {
    var stopID: String
    var status = NativeTripVisitStatus.pending
    var arrivedAt: Date?
    var startedAt: Date?
    var departedAt: Date?
    var plannedLeaveAt: Date?
}

struct NativeTripActualLeg: Codable, Sendable {
    var fromID: String
    var toID: String
    var departedAt: Date
    var arrivedAt: Date
}

enum NativeTripActiveCommand: Codable, Sendable {
    case arrive(String)
    case beginVisit(String)
    case depart(String)
    case extend(Int)
    case setLeave(Date)
    case skip(String)
    case deadline(Date)
    case apply(UUID)
    case reject(UUID)
    case finish
    case advanceSimulation(Int)

    var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(self).base64EncodedString()) ?? "invalid"
    }
    var event: String {
        switch self {
        case .arrive: "visit.arrived"
        case .beginVisit: "visit.started"
        case .depart: "visit.completed"
        case .extend, .setLeave: "visit.extended"
        case .skip: "visit.skipped"
        case .deadline: "trip.deadline_changed"
        case .apply: "proposal.applied"
        case .reject: "proposal.rejected"
        case .finish: "trip.completed"
        case .advanceSimulation: "simulation.advanced"
        }
    }
}

struct NativeTripActionReceipt: Codable, Sendable {
    var actionID: String
    var signature: String
    var resultingRevision: Int
    var at: Date
    var event: String
}

struct NativeTripReplanProjection: Codable, Sendable {
    var requestID = UUID()
    var baseRevision: Int
    var asOf: Date
    var draft: NativeTripDraft
    var retainedOrder: [String]
    var currentConflicts: [String]
    var currentRemainingSeconds: Double
}

struct NativeTripReplanProposal: Codable, Sendable, Identifiable {
    var id = UUID()
    var producerSessionID: UUID
    var projection: NativeTripReplanProjection
    var report: NativeTripReport
    var baseline: NativeTripCandidate?

    var canApply: Bool { report.fastest?.feasible == true && projection.currentConflicts.isEmpty }
    var totalRemainingMinutes: Double? {
        report.fastest.map { $0.elapsedMinutes + projection.currentRemainingSeconds / 60 }
    }
}

struct NativeTripActiveTrip: Codable, Sendable {
    var inputRevision = 0
    var startedAt: Date
    var lastEventAt: Date
    var finishedAt: Date?
    var finishBy: Date
    var visits: [NativeTripVisitState]
    var actualLegs: [NativeTripActualLeg] = []
    var acceptedOrder: [String]
    var acceptedRemaining: NativeTripReport?
    var needsReplan = true
    var proposal: NativeTripReplanProposal?
    var receipts: [NativeTripActionReceipt] = []
    var simulationNow: Date?

    var isActive: Bool { finishedAt == nil }
    var current: NativeTripVisitState? {
        visits.first { $0.status == .arrived || $0.status == .visiting }
    }
    var lastCompleted: NativeTripVisitState? {
        for leg in actualLegs.reversed() {
            if let visit = visits.first(where: { $0.stopID == leg.toID && $0.status == .completed }) {
                return visit
            }
        }
        return nil
    }
    var pendingIDs: [String] {
        acceptedOrder.filter { id in visits.contains { $0.stopID == id && $0.status == .pending } }
    }

    static func start(report: NativeTripReport, at: Date) throws -> Self {
        try NativeTripLocalSession.validateAccepted(report)
        try validateMode(report.draft)
        guard at.timeIntervalSince1970.isFinite,
              report.draft.calendar.isDate(at, inSameDayAs: report.draft.departure),
              at < report.draft.endOfDay
        else { throw NativeTripError.message("Mulai perjalanan pada tanggal trip yang dipilih.") }
        return .init(
            startedAt: at, lastEventAt: at, finishBy: report.draft.deadline,
            visits: report.fastest!.order.map { .init(stopID: $0) }, acceptedOrder: report.fastest!.order,
            simulationNow: report.simulationKind == "active" ? at : nil)
    }

    static func validateMode(_ draft: NativeTripDraft) throws {
        guard draft.modes.count == 1, draft.modes[0] != .transit, !draft.usesPrivateCar else {
            throw NativeTripError.message(
                "PoC trip aktif memakai satu moda: jalan kaki atau taksi/ride-hailing. Mobil pribadi dan transit belum didukung pada alur aktif."
            )
        }
    }

    func projection(original: NativeTripReport, at: Date, anchorConfirmed: Bool) throws
        -> NativeTripReplanProjection
    {
        try validate(original: original)
        guard isActive, anchorConfirmed else {
            throw NativeTripError.message(
                "Konfirmasi lokasi awal perhitungan sebelum menghitung sisa trip.")
        }
        guard at.timeIntervalSince1970.isFinite, at >= lastEventAt,
              original.draft.calendar.isDate(at, inSameDayAs: original.draft.departure)
        else {
            throw NativeTripError.message(
                "Waktu sekarang tidak konsisten atau perjalanan melewati hari layanan. Fakta tersimpan tetap dipertahankan."
            )
        }
        try Self.validateMode(original.draft)
        let byID = Dictionary(uniqueKeysWithValues: original.draft.stops.map { ($0.id, $0) })
        var anchor = original.draft.origin
        var departure = at
        var conflicts: [String] = []
        if let current {
            let stop = byID[current.stopID]!
            anchor = stop.point
            if current.status == .arrived {
                let start = max(
                    at, stop.opening?.opensMinute.map { original.draft.clockDate(minutes: $0) } ?? at)
                departure = max(
                    start.addingTimeInterval(
                        Double(stop.dwell(defaultMinutes: original.draft.defaultDwell)) * 60),
                    current.plannedLeaveAt ?? start)
            } else {
                departure = max(at, current.plannedLeaveAt!)
            }
            if let closes = stop.opening?.closesMinute, stop.role == .visit,
               departure > original.draft.clockDate(minutes: closes)
            {
                conflicts.append("\(stop.point.title): waktu keluar melewati jam tutup yang diketahui.")
            }
        } else if let last = lastCompleted {
            anchor = byID[last.stopID]!.point
        }
        guard departure < original.draft.endOfDay, finishBy > departure else {
            throw NativeTripError.message(
                "Sisa trip tidak muat: waktu keluar/sekarang sudah mencapai batas tiba. Ubah batas selesai atau durasi secara eksplisit."
            )
        }
        var draft = original.draft
        draft.origin = anchor
        draft.returnsToOrigin = false
        draft.end = original.draft.endPoint
        draft.departure = departure
        draft.finishBy = finishBy
        draft.stops = pendingIDs.map { byID[$0]! }
        draft.routingAlgorithm = "hybrid"
        try draft.validate(allowNoStops: true)
        return .init(
            baseRevision: inputRevision, asOf: at, draft: draft, retainedOrder: pendingIDs,
            currentConflicts: conflicts, currentRemainingSeconds: departure.timeIntervalSince(at))
    }

    func warnings(original: NativeTripReport) -> [String] {
        var warnings: [String] = []
        for visit in visits {
            guard let stop = original.draft.stops.first(where: { $0.id == visit.stopID }) else {
                continue
            }
            if let started = visit.startedAt, let opens = stop.opening?.opensMinute,
               started < original.draft.clockDate(minutes: opens)
            {
                warnings.append(
                    "\(stop.point.title): pengguna melaporkan mulai sebelum jam buka. Fakta aktual dipertahankan."
                )
            }
            if let ended = visit.departedAt, let closes = stop.opening?.closesMinute,
               ended > original.draft.clockDate(minutes: closes)
            {
                warnings.append("\(stop.point.title): kunjungan aktual berakhir setelah jam tutup.")
            }
        }
        if let finishedAt, finishedAt > finishBy {
            warnings.append("Tiba aktual melewati batas selesai.")
        }
        return warnings
    }

    /// All mutation occurs on a value copy. The caller publishes only after an atomic commit.
    mutating func perform(
        _ command: NativeTripActiveCommand, actionID: String, at: Date,
        original: NativeTripReport, runtimeSessionID: UUID
    ) throws {
        var next = self
        try next.reduce(
            command, actionID: actionID, at: at, original: original, runtimeSessionID: runtimeSessionID)
        self = next
    }

    private mutating func reduce(
        _ command: NativeTripActiveCommand, actionID: String, at: Date,
        original: NativeTripReport, runtimeSessionID: UUID
    ) throws {
        if let receipt = receipts.first(where: { $0.actionID == actionID }) {
            guard receipt.signature == command.signature else {
                throw NativeTripError.message(
                    "Identitas tindakan sudah digunakan untuk perubahan yang berbeda.")
            }
            return
        }
        guard isActive, at.timeIntervalSince1970.isFinite, at >= lastEventAt, receipts.count < 1000
        else {
            throw NativeTripError.message(
                "Tindakan tidak berlaku: trip selesai, waktu mundur, atau batas tindakan PoC tercapai.")
        }
        if simulationNow != nil { simulationNow = at }
        let byID = Dictionary(uniqueKeysWithValues: original.draft.stops.map { ($0.id, $0) })
        switch command {
        case .arrive(let id):
            guard current == nil, pendingIDs.first == id,
                  let index = visits.firstIndex(where: { $0.stopID == id })
            else {
                throw NativeTripError.message(
                    "Selesaikan kunjungan saat ini dan ikuti tujuan berikutnya pada rencana.")
            }
            let previous = lastCompleted
            actualLegs.append(
                .init(
                    fromID: previous?.stopID ?? original.draft.origin.id, toID: id,
                    departedAt: previous?.departedAt ?? startedAt, arrivedAt: at))
            visits[index].status = .arrived
            visits[index].arrivedAt = at
        case .beginVisit(let id):
            guard let index = visits.firstIndex(where: { $0.stopID == id && $0.status == .arrived })
            else { throw NativeTripError.message("Catat tiba sebelum memulai kunjungan.") }
            visits[index].status = .visiting
            visits[index].startedAt = at
            visits[index].plannedLeaveAt = at.addingTimeInterval(
                Double(byID[id]!.dwell(defaultMinutes: original.draft.defaultDwell)) * 60)
        case .depart(let id):
            guard let index = visits.firstIndex(where: { $0.stopID == id && $0.status == .visiting })
            else { throw NativeTripError.message("Mulai kunjungan sebelum menandainya selesai.") }
            visits[index].departedAt = at
            visits[index].status = .completed
        case .extend(let minutes):
            guard (1 ... 480).contains(minutes),
                  let index = visits.firstIndex(where: { $0.status == .visiting })
            else {
                throw NativeTripError.message(
                    "Tambahan durasi berlaku pada kunjungan yang sedang berjalan.")
            }
            visits[index].plannedLeaveAt = max(at, visits[index].plannedLeaveAt!).addingTimeInterval(
                Double(minutes) * 60)
        case .setLeave(let leave):
            guard leave.timeIntervalSince1970.isFinite, leave >= at,
                  let index = visits.firstIndex(where: { $0.status == .visiting })
            else {
                throw NativeTripError.message(
                    "Waktu keluar harus sekarang atau setelahnya, pada kunjungan yang sedang berjalan.")
            }
            visits[index].plannedLeaveAt = leave
        case .skip(let id):
            guard let index = visits.firstIndex(where: { $0.stopID == id && $0.status == .pending })
            else { throw NativeTripError.message("Hanya tujuan yang belum dikunjungi dapat dilewati.") }
            visits[index].status = .skipped
        case .deadline(let date):
            guard date.timeIntervalSince1970.isFinite, date > original.draft.departure,
                  date <= original.draft.endOfDay
            else {
                throw NativeTripError.message(
                    "Batas tiba harus berada setelah awal trip dan dalam hari yang sama.")
            }
            finishBy = date
        case .apply(let id):
            guard let proposal, proposal.id == id, proposal.canApply,
                  proposal.producerSessionID == runtimeSessionID,
                  proposal.projection.baseRevision == inputRevision,
                  at >= proposal.projection.asOf,
                  at.timeIntervalSince(proposal.projection.draft.departure) <= 60
            else {
                throw NativeTripError.message(
                    "Usulan sudah kedaluwarsa, berubah, atau belum layak. Hitung ulang sebelum menerapkan.")
            }
            let expected = try projection(
                original: original, at: proposal.projection.asOf, anchorConfirmed: true)
            guard expected.currentConflicts.isEmpty,
                  expected.currentConflicts == proposal.projection.currentConflicts,
                  expected.draft == proposal.projection.draft,
                  expected.retainedOrder == proposal.projection.retainedOrder,
                  proposal.report.draft == expected.draft
            else { throw NativeTripError.message("Konteks usulan tidak cocok dengan perjalanan.") }
            try NativeTripLocalSession.validateAccepted(proposal.report, allowNoStops: true)
            acceptedRemaining = proposal.report
            acceptedOrder = proposal.report.fastest!.order
            needsReplan = false
        case .reject(let id):
            guard proposal?.id == id else {
                throw NativeTripError.message("Usulan sudah tidak tersedia.")
            }
        case .finish:
            guard current == nil, pendingIDs.isEmpty else {
                throw NativeTripError.message(
                    "Selesaikan atau lewati tujuan tersisa sebelum mengonfirmasi tiba di titik akhir.")
            }
            let previous = lastCompleted
            actualLegs.append(
                .init(
                    fromID: previous?.stopID ?? original.draft.origin.id, toID: original.draft.endPoint.id,
                    departedAt: previous?.departedAt ?? startedAt, arrivedAt: at))
            finishedAt = at
        case .advanceSimulation(let minutes):
            guard let simulated = simulationNow, (1 ... 480).contains(minutes) else {
                throw NativeTripError.message("Jam simulasi hanya tersedia untuk contoh sintetis.")
            }
            simulationNow = simulated.addingTimeInterval(Double(minutes) * 60)
        }
        if case .apply = command {} else if case .reject = command {} else { needsReplan = true }
        proposal = nil
        inputRevision += 1
        lastEventAt = at
        receipts.append(
            .init(
                actionID: actionID, signature: command.signature, resultingRevision: inputRevision, at: at,
                event: command.event))
        try validate(original: original)
    }

    func validate(original: NativeTripReport) throws {
        try Self.validateMode(original.draft)
        let ids = Set(original.draft.stops.map(\.id))
        guard visits.count == ids.count, Set(visits.map(\.stopID)) == ids,
              Set(acceptedOrder).count == acceptedOrder.count,
              Set(acceptedOrder).isSubset(of: ids),
              visits.filter({ $0.status == .arrived || $0.status == .visiting }).count <= 1,
              visits.filter({ $0.status == .pending }).allSatisfy({ acceptedOrder.contains($0.stopID) }),
              startedAt.timeIntervalSince1970.isFinite, lastEventAt >= startedAt,
              finishBy > original.draft.departure, finishBy <= original.draft.endOfDay,
              inputRevision == receipts.count, Set(receipts.map(\.actionID)).count == receipts.count,
              receipts.enumerated().allSatisfy({
                  $0.element.resultingRevision == $0.offset + 1 && $0.element.at <= lastEventAt
                      && $0.element.at >= startedAt
              }),
              simulationNow.map({ $0.timeIntervalSince1970.isFinite && $0 >= lastEventAt }) != false
        else { throw NativeTripError.message("State perjalanan aktif tidak konsisten.") }
        for visit in visits {
            let dates = [visit.arrivedAt, visit.startedAt, visit.departedAt, visit.plannedLeaveAt]
                .compactMap { $0 }
            guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
                  visit.arrivedAt.map({ $0 >= startedAt && $0 <= lastEventAt }) != false,
                  visit.startedAt.map({ $0 >= (visit.arrivedAt ?? .distantFuture) && $0 <= lastEventAt })
                  != false,
                  visit.departedAt.map({ $0 >= (visit.startedAt ?? .distantFuture) && $0 <= lastEventAt })
                  != false
            else { throw NativeTripError.message("Waktu aktual kunjungan tidak konsisten.") }
            switch visit.status {
            case .pending, .skipped:
                guard visit.arrivedAt == nil, visit.startedAt == nil, visit.departedAt == nil else {
                    throw NativeTripError.message(
                        "Tujuan pending/skip tidak boleh mempunyai kunjungan aktual rekaan.")
                }
            case .arrived:
                guard visit.arrivedAt != nil, visit.startedAt == nil, visit.departedAt == nil else {
                    throw NativeTripError.message("State tiba tidak valid.")
                }
            case .visiting:
                guard visit.startedAt != nil, visit.plannedLeaveAt != nil, visit.departedAt == nil else {
                    throw NativeTripError.message("State kunjungan tidak valid.")
                }
            case .completed:
                guard visit.departedAt != nil else {
                    throw NativeTripError.message("Kunjungan selesai memerlukan waktu aktual.")
                }
            }
        }
        guard
            actualLegs.allSatisfy({
                $0.departedAt >= startedAt && $0.arrivedAt >= $0.departedAt && $0.arrivedAt <= lastEventAt
            }),
            finishedAt.map({
                $0 >= startedAt && $0 <= lastEventAt && current == nil && pendingIDs.isEmpty
            }) != false
        else { throw NativeTripError.message("Riwayat perpindahan aktual tidak konsisten.") }
        var fromID = original.draft.origin.id
        var departure = startedAt
        var seen = Set<String>()
        let visitLegs = finishedAt == nil ? actualLegs : Array(actualLegs.dropLast())
        for leg in visitLegs {
            guard leg.fromID == fromID, leg.departedAt == departure,
                  seen.insert(leg.toID).inserted,
                  let visit = visits.first(where: { $0.stopID == leg.toID }),
                  visit.arrivedAt == leg.arrivedAt
            else { throw NativeTripError.message("Ruas aktual tidak cocok dengan fakta kunjungan.") }
            fromID = leg.toID
            if let departed = visit.departedAt {
                departure = departed
            } else if leg.toID != visitLegs.last?.toID {
                throw NativeTripError.message("Perpindahan berikutnya tercatat sebelum kunjungan selesai.")
            }
        }
        guard seen == Set(visits.filter { $0.arrivedAt != nil }.map(\.stopID)) else {
            throw NativeTripError.message(
                "Fakta kedatangan tidak mempunyai riwayat perpindahan yang konsisten.")
        }
        if let finishedAt {
            guard let leg = actualLegs.last, leg.fromID == fromID, leg.toID == original.draft.endPoint.id,
                  leg.departedAt == departure, leg.arrivedAt == finishedAt
            else { throw NativeTripError.message("Ruas akhir aktual tidak konsisten.") }
        }
        if let acceptedRemaining {
            try NativeTripLocalSession.validateAccepted(acceptedRemaining, allowNoStops: true)
        }
    }
}
