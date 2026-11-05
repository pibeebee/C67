import Foundation
import Observation
import CloudKit

@MainActor protocol JourneyPlanTransport {
    func publishPlan(_ plan: JourneyPlan, to ref: CloudReference) async throws
    func fetchPlan(_ ref: CloudReference) async throws -> JourneyPlan?
}

@MainActor @Observable final class JourneyPlanSync {
    let store: SessionStore
    private let transport: any JourneyPlanTransport
    private(set) var publishing = false
    private(set) var fetching = false
    private(set) var status = "Rundown tersimpan di perangkat ini"
    private(set) var lastReceivedAt: Date?
    private var published: [String: Int] = [:]
    init(store: SessionStore, transport: (any JourneyPlanTransport)? = nil) {
        self.store = store; self.transport = transport ?? CloudLocationChannel()
        if store.state.joinedQR != nil { status = "Salinan tersimpan · tunggu pemeriksaan koneksi untuk pembaruan" }
        else if store.state.mode == .simulation { status = "SIMULASI · tidak dikirim ke CloudKit" }
    }
    func publish() async {
        guard !publishing, store.state.mode == .real, store.state.joinedQR == nil else { return }
        let run = store.state.runID
        let refs = store.state.leaderShares?.map(\.reference) ?? []
        guard !refs.isEmpty else { status = "Tersimpan lokal · menunggu peserta terhubung"; return }
        publishing = true; defer { publishing = false }
        let plan = store.state.effectivePlan
        var failed = false
        for ref in refs {
            guard !Task.isCancelled, store.state.runID == run else { return }
            let key = "\(run)|\(ref.zoneName)"
            guard published[key] != plan.revision else { continue }
            do {
                try await transport.publishPlan(plan, to: ref)
                guard store.state.runID == run, store.state.leaderShares?.contains(where: { $0.reference == ref }) == true else { continue }
                published[key] = plan.revision
            } catch let error as CKError where [.zoneNotFound, .unknownItem, .permissionFailure].contains(error.code) {
                failed = true // A revoked/partial channel must not block other participants.
            } catch { failed = true; break }
        }
        guard store.state.runID == run else { return }
        let current = store.state.effectivePlan
        let shares = store.state.leaderShares ?? []
        let count = shares.filter { published["\(run)|\($0.reference.zoneName)"] == current.revision }.count
        status = failed || count < shares.count ? "Tersimpan lokal · \(count)/\(shares.count) kanal cloud diperbarui. Coba sinkronkan lagi." : "Versi \(current.revision) tersimpan di \(count) kanal cloud · penerimaan peserta belum dikonfirmasi"
    }
    func fetch() async {
        guard !fetching, store.state.mode == .real, let ref = store.state.leaderBinding else { return }
        fetching = true; defer { fetching = false }
        do {
            guard let plan = try await transport.fetchPlan(ref) else {
                status = "Rundown belum tersedia dari TL · titik lama mungkin salinan saat bergabung"; return
            }
            guard !Task.isCancelled, store.state.leaderBinding == ref, store.state.runID == ref.runID else { return }
            try store.commit { try $0.receivePlan(plan) }
            lastReceivedAt = .now
            status = "Diperiksa \(Date.now.formatted(date: .omitted, time: .standard)) · versi \(store.state.effectivePlan.revision)"
        } catch {
            guard store.state.leaderBinding == ref else { return }
            status = "Belum dapat memperbarui rundown · salinan tersimpan mungkin lama. Coba refresh saat online."
        }
    }
}

extension CloudLocationChannel: JourneyPlanTransport {
    private func planID(_ ref: CloudReference) -> CKRecord.ID {
        CKRecord.ID(recordName: "JourneyPlan", zoneID: CKRecordZone.ID(zoneName: ref.zoneName, ownerName: ref.ownerName))
    }
    func publishPlan(_ plan: JourneyPlan, to ref: CloudReference) async throws {
        try available(); try plan.validate(for: ref.runID)
        guard ref.participantID == "TL", ref.ownerName == CKCurrentUserDefaultName else { throw POCError.message("Rundown hanya ditulis pada kanal milik TL.") }
        let payload = try JSONEncoder().encode(plan)
        guard payload.count <= 200_000 else { throw POCError.message("Rundown terlalu besar untuk POC.") }
        let db = sharingContainer.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: ref.rootName, zoneID: planID(ref).zoneID)
        let root = try await db.record(for: rootID)
        guard root["runID"] as? String == plan.runID.uuidString, root["participantID"] as? String == "TL" else { throw POCError.message("Kanal rundown tidak cocok.") }
        let record: CKRecord
        do { record = try await db.record(for: planID(ref)) }
        catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "LatestLocation", recordID: planID(ref))
            record.parent = CKRecord.Reference(recordID: rootID, action: .none)
        }
        if let data = record["payload"] as? Data {
            let previous = try JSONDecoder().decode(JourneyPlan.self, from: data)
            try previous.validate(for: ref.runID)
            guard previous.revision <= plan.revision else { throw POCError.message("Cloud memiliki versi rundown yang lebih baru.") }
            if previous.revision == plan.revision {
                guard previous == plan else { throw POCError.message("Versi rundown cloud bentrok.") }
                return
            }
        }
        try Task.checkCancellation()
        record["payload"] = payload as CKRecordValue
        try await save([record], in: db)
    }
    func fetchPlan(_ ref: CloudReference) async throws -> JourneyPlan? {
        try available()
        guard .now >= retryAfter else { throw POCError.message("CloudKit sedang backoff.") }
        guard ref.participantID == "TL" else { throw POCError.message("Kanal ini bukan rundown TL.") }
        let db = sharingContainer.sharedCloudDatabase
        let root = try await db.record(for: CKRecord.ID(recordName: ref.rootName, zoneID: planID(ref).zoneID))
        guard root["runID"] as? String == ref.runID.uuidString, root["participantID"] as? String == "TL" else { throw POCError.message("Kanal rundown berbeda.") }
        let record: CKRecord
        do { record = try await db.record(for: planID(ref)) }
        catch let error as CKError where error.code == .unknownItem { return nil }
        guard let data = record["payload"] as? Data, data.count <= 200_000 else { throw POCError.message("Payload rundown tidak tersedia/terlalu besar.") }
        let plan = try JSONDecoder().decode(JourneyPlan.self, from: data)
        try plan.validate(for: ref.runID)
        return plan
    }
}
