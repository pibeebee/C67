import CloudKit
import Observation

struct OwnerShare {
    var share: CKShare
    var recipient: String
    var accepted: Bool
}

struct RemoteLocation {
    var sample: LocationSample?
    var epoch: UUID?
    var expiresAt: Date
    var state: String
}

@MainActor @Observable final class CloudLocationChannel {
    static let containerID = "iCloud.giovanchristoffel.poc-c67"
    private(set) var account = "Belum diperiksa"
    private(set) var lastError: String?
    private(set) var retryAfter: Date = .distantPast
    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    var sharingContainer: CKContainer { container }

    func available() throws {
        #if targetEnvironment(simulator)
            throw POCError.message("Gunakan dua iPhone fisik untuk CloudKit. Di Simulator, gunakan mode Simulasi atau pemeriksaan lokal.")
        #endif
    }
    func checkAccount() async throws {
        try available()
        let status = try await container.accountStatus()
        switch status {
        case .available: account = "iCloud tersedia"
        case .noAccount: account = "Belum masuk iCloud"
        case .restricted: account = "Akun iCloud dibatasi"
        case .temporarilyUnavailable: account = "iCloud sementara tidak tersedia"
        case .couldNotDetermine: account = "Status iCloud tidak dapat dinilai"
        @unknown default: account = "Status iCloud tidak diketahui"
        }
        guard status == .available else { throw POCError.message(account + ". Alur manual tetap tersedia.") }
    }
    func accountRecordName() async throws -> String {
        try await checkAccount()
        return try await container.userRecordID().recordName
    }
    func inviteLeader(_ ref: CloudReference, recordName: String) async throws -> CKShare {
        let info = try await ownerShare(ref)
        let leader = try await container.shareParticipant(forUserRecordID: CKRecord.ID(recordName: recordName))
        guard leader.userIdentity.userRecordID?.recordName == recordName,
              info.share.owner.userIdentity.userRecordID?.recordName != recordName else {
            throw POCError.message("Gunakan akun iCloud TL yang berbeda dari peserta.")
        }
        let others = info.share.participants.filter { $0.role != .owner }
        guard others.allSatisfy({ $0.userIdentity.userRecordID?.recordName == recordName }) else {
            throw POCError.message("Share sudah mempunyai penerima lain. Cleanup sebelum scan ulang.")
        }
        leader.permission = .readOnly
        info.share.addParticipant(leader)
        try await save([info.share], in: container.privateCloudDatabase)
        guard let saved = try await container.privateCloudDatabase.record(for: info.share.recordID) as? CKShare,
              saved.url != nil else { throw POCError.message("Undangan privat belum siap. Coba lagi.") }
        return saved
    }
    func makeReference(runID: UUID, participantID: String) -> CloudReference {
        CloudReference(runID: runID, participantID: participantID, zoneName: "C67-" + UUID().uuidString,
                       ownerName: CKCurrentUserDefaultName, rootName: "LocationShare", shareName: UUID().uuidString, latestName: "LatestLocation")
    }
    private func zoneID(_ r: CloudReference) -> CKRecordZone.ID { CKRecordZone.ID(zoneName: r.zoneName, ownerName: r.ownerName) }
    private func id(_ name: String, _ r: CloudReference) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID(r)) }
    func save(_ records: [CKRecord], in db: CKDatabase) async throws {
        guard .now >= retryAfter else { throw POCError.message("CloudKit backoff sampai \(retryAfter.formatted(date: .omitted, time: .standard)).") }
        do {
            let result = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            for item in result.saveResults.values { _ = try item.get() }
            lastError = nil
        } catch {
            note(error); throw error
        }
    }
    func note(_ error: Error) {
        let ns = error as NSError
        // Store codes only; CloudKit error descriptions can contain record/account identifiers.
        lastError = "\(ns.domain) code=\(ns.code)"
        let delay = (ns.userInfo[CKErrorRetryAfterKey] as? Double) ?? 5
        retryAfter = .now.addingTimeInterval(max(5, delay))
    }
    func prepare(_ ref: CloudReference) async throws -> CKShare {
        try await checkAccount()
        let db = container.privateCloudDatabase
        _ = try await db.save(CKRecordZone(zoneID: zoneID(ref)))
        let root = CKRecord(recordType: "LocationShare", recordID: id(ref.rootName, ref))
        root["runID"] = ref.runID.uuidString
        root["participantID"] = ref.participantID
        root["state"] = "ready"
        root["expiresAt"] = Date.distantPast as CKRecordValue
        root["latestName"] = ref.latestName
        let latest = CKRecord(recordType: "LatestLocation", recordID: id(ref.latestName, ref))
        latest.parent = CKRecord.Reference(recordID: root.recordID, action: .none)
        let share = CKShare(rootRecord: root, shareID: id(ref.shareName, ref))
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "C67 · \(ref.participantID) · \(ref.runID.uuidString.prefix(8))"
        try await save([root, latest, share], in: db)
        return try await db.record(for: share.recordID) as? CKShare ?? share
    }
    func ownerShare(_ ref: CloudReference) async throws -> OwnerShare {
        try available()
        guard let share = try await container.privateCloudDatabase.record(for: id(ref.shareName, ref)) as? CKShare else {
            throw POCError.message("Share tidak ditemukan. Coba cleanup dan siapkan ulang.")
        }
        guard share.publicPermission == .none else { throw POCError.message("Share harus privat; Anyone with link tidak diperbolehkan.") }
        let others = share.participants.filter { $0.role != .owner }
        guard others.count <= 1, others.allSatisfy({ $0.permission == .readOnly }) else {
            throw POCError.message("POC memerlukan tepat satu TL dengan akses read-only. Perbaiki penerima pada Kelola undangan.")
        }
        let person = others.first
        let name = person?.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? "TL yang diundang"
        return OwnerShare(share: share, recipient: name, accepted: person?.acceptanceStatus == .accepted)
    }
    func begin(_ ref: CloudReference, epoch: UUID, expiresAt: Date, leaderSource: Bool = false) async throws {
        let checked = try await ownerShare(ref)
        guard checked.accepted || (leaderSource && ref.participantID == "TL") else { throw POCError.message("TL belum menerima undangan. Periksa penerima lagi setelah undangan diterima.") }
        let db = container.privateCloudDatabase
        let root = try await db.record(for: id(ref.rootName, ref))
        let latest = try await db.record(for: id(ref.latestName, ref))
        root["epoch"] = epoch.uuidString; root["state"] = "active"; root["expiresAt"] = expiresAt as CKRecordValue
        for key in latest.allKeys() { latest[key] = nil }
        try await save([root, latest], in: db)
    }
    func upload(_ sample: LocationSample, ref: CloudReference, expiresAt: Date) async throws {
        try available()
        guard LocationRules.mayUpload(sample, activeEpoch: sample.epoch, runID: ref.runID, expiresAt: expiresAt) else { throw POCError.message("Sampel tidak lagi boleh diunggah.") }
        let db = container.privateCloudDatabase
        let root = try await db.record(for: id(ref.rootName, ref))
        guard root["state"] as? String == "active", root["epoch"] as? String == sample.epoch.uuidString,
              let deadline = root["expiresAt"] as? Date, Date.now < deadline else { throw POCError.message("Cloud lease sudah berakhir/berubah.") }
        let latest = try await db.record(for: id(ref.latestName, ref))
        try Task.checkCancellation()
        latest["payload"] = try JSONEncoder().encode(sample) as CKRecordValue
        // Include the unchanged root as a condition, protecting against a conflicting stop/new epoch.
        try await save([root, latest], in: db)
    }
    func pause(_ ref: CloudReference) async throws {
        try available()
        let db = container.privateCloudDatabase
        let root = try await db.record(for: id(ref.rootName, ref))
        let latest = try await db.record(for: id(ref.latestName, ref))
        root["state"] = "paused"; root["expiresAt"] = Date.distantPast as CKRecordValue; root["epoch"] = nil
        for key in latest.allKeys() { latest[key] = nil }
        try await save([root, latest], in: db)
    }
    func metadata(for urlText: String) async throws -> CKShare.Metadata {
        try available()
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              ["icloud.com", "www.icloud.com"].contains(url.host?.lowercased() ?? ""), url.path.hasPrefix("/share/") else {
            throw POCError.message("Masukkan URL undangan https://www.icloud.com/share/…")
        }
        return try await container.shareMetadata(for: url)
    }
    func accept(_ metadata: CKShare.Metadata, expectedRunID: UUID? = nil, expectedParticipantID: String? = nil, expectedOwnerRecord: String? = nil) async throws -> CloudReference {
        try await checkAccount()
        guard metadata.containerIdentifier == Self.containerID else { throw POCError.message("Undangan berasal dari container lain.") }
        guard let rootID = metadata.hierarchicalRootRecordID else { throw POCError.message("Undangan tidak mempunyai root record.") }
        guard metadata.share.publicPermission == .none else { throw POCError.message("Undangan harus privat.") }
        if let expectedOwnerRecord {
            guard metadata.ownerIdentity.userRecordID?.recordName == expectedOwnerRecord else { throw POCError.message("Pemilik undangan tidak cocok dengan peserta pairing.") }
        }
        let share = try await container.accept(metadata)
        guard share.currentUserParticipant?.permission == .readOnly else { throw POCError.message("TL harus mendapat izin read-only.") }
        let root = try await container.sharedCloudDatabase.record(for: rootID)
        guard let runString = root["runID"] as? String, let run = UUID(uuidString: runString),
              let participantID = root["participantID"] as? String, let latestName = root["latestName"] as? String else {
            throw POCError.message("Metadata run tidak valid.")
        }
        if let expectedRunID { guard run == expectedRunID else { throw POCError.message("Run undangan berbeda.") } }
        if let expectedParticipantID { guard participantID == expectedParticipantID else { throw POCError.message("ID undangan berbeda.") } }
        return CloudReference(runID: run, participantID: participantID, zoneName: rootID.zoneID.zoneName,
                              ownerName: rootID.zoneID.ownerName, rootName: rootID.recordName, shareName: share.recordID.recordName, latestName: latestName)
    }
    func fetch(_ ref: CloudReference) async throws -> RemoteLocation {
        try available()
        guard .now >= retryAfter else { throw POCError.message("CloudKit sedang backoff.") }
        let db = container.sharedCloudDatabase
        let root = try await db.record(for: id(ref.rootName, ref))
        guard root["runID"] as? String == ref.runID.uuidString else { throw POCError.message("Run cloud tidak cocok.") }
        let epoch = (root["epoch"] as? String).flatMap(UUID.init(uuidString:))
        let expiresAt = root["expiresAt"] as? Date ?? .distantPast
        let state = root["state"] as? String ?? "unknown"
        guard state == "active", Date.now < expiresAt else { return RemoteLocation(sample: nil, epoch: epoch, expiresAt: expiresAt, state: state) }
        let latest = try await db.record(for: id(ref.latestName, ref))
        let sample = try (latest["payload"] as? Data).map { try JSONDecoder().decode(LocationSample.self, from: $0) }
        return RemoteLocation(sample: sample, epoch: epoch, expiresAt: expiresAt, state: state)
    }
    func revokeAndDelete(_ ref: CloudReference) async throws {
        try available()
        guard ref.ownerName == CKCurrentUserDefaultName, ref.zoneName.hasPrefix("C67-") else { throw POCError.message("Cleanup hanya untuk zone privat yang dibuat POC ini.") }
        do { _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID(ref)) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { return }
    }
    func leave(_ ref: CloudReference) async throws {
        try available()
        do { _ = try await container.sharedCloudDatabase.deleteRecord(withID: id(ref.shareName, ref)) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { return }
    }
    func probeWriteDenied(_ ref: CloudReference) async throws -> Bool {
        try available()
        let db = container.sharedCloudDatabase
        let record = try await db.record(for: id(ref.rootName, ref))
        record["writeProbe"] = UUID().uuidString
        do { try await save([record], in: db); return false }
        catch let error as CKError where error.code == .permissionFailure { return true }
    }
}
