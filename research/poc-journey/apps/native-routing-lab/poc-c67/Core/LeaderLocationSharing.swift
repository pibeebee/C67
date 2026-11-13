import Foundation
import CloudKit
import Observation

// Each participant receives a separate read-only share containing only the TL's position.
@MainActor @Observable final class LeaderLocationSharing {
    let store: SessionStore
    let sensor = LocationService()
    let cloud = CloudLocationChannel()
    private(set) var status = "Lokasi TL belum dibagikan"
    private(set) var busy = false
    private(set) var pausePending = false
    private(set) var expiresAt: Date?
    var durationMinutes = 30.0
    var backgroundEnabled = true
    private var epoch: UUID?
    private var pending: LocationSample?
    private var upload: Task<Void, Never>?
    private var lastUpload = Date.distantPast
    private var stopRequested = false
    var hasConnections: Bool { !(store.state.leaderShares ?? []).isEmpty }
    var locked: Bool { busy || sensor.running || pausePending || upload != nil }
    init(store: SessionStore) {
        self.store = store
        sensor.onSample = { [weak self] sample in self?.schedule(sample) }
        sensor.onExpiration = { [weak self] in Task { await self?.stop() } }
        if hasConnections { status = "Koneksi TL tersimpan; GPS OFF. Mulai sesi baru dengan persetujuan." }
    }
    func ensureRecipient(account: String) async throws -> String {
        guard !busy, !pausePending, store.state.mode == .real, store.state.qrMembers != nil else { throw POCError.message("Tunggu operasi lokasi TL selesai sebelum pairing.") }
        busy = true; defer { busy = false }
        let runID = store.state.runID
        let existing = store.state.leaderShares?.first { $0.accountRecord == account }
        let ref: CloudReference
        if let existing { ref = existing.reference }
        else {
            guard (store.state.leaderShares?.count ?? 0) < 20 else { throw POCError.message("Koneksi lokasi TL penuh. Hapus koneksi pairing yang tidak selesai terlebih dahulu.") }
            ref = cloud.makeReference(runID: runID, participantID: "TL")
            try store.commit { if $0.leaderShares == nil { $0.leaderShares = [] }; $0.leaderShares?.append(LeaderShare(accountRecord: account, reference: ref)) }
            _ = try await cloud.prepare(ref)
        }
        guard store.state.runID == runID, !stopRequested else { throw POCError.message("Pairing lokasi TL dibatalkan. Selesaikan penghentian dahulu.") }
        let share = try await cloud.inviteLeader(ref, recordName: account)
        if let epoch, let expiresAt, sensor.running, expiresAt > .now {
            try await cloud.begin(ref, epoch: epoch, expiresAt: expiresAt, leaderSource: true)
        }
        try await cloud.publishPlan(store.state.effectivePlan, to: ref)
        guard let url = share.url else { throw POCError.message("URL lokasi TL belum tersedia.") }
        return url.absoluteString
    }
    func start(consent: Bool) async throws {
        guard consent, !busy, !pausePending, !sensor.running, upload == nil,
              store.state.mode == .real, store.state.qrMembers != nil, !store.state.ended,
              let shares = store.state.leaderShares, !shares.isEmpty else { throw POCError.message("Hubungkan peserta lewat QR, konfirmasi persetujuan TL, dan selesaikan operasi lama dahulu.") }
        busy = true; stopRequested = false
        defer { busy = false }
        let epoch = UUID(), deadline = Date.now.addingTimeInterval(durationMinutes * 60)
        do {
            for share in shares {
                try await cloud.begin(share.reference, epoch: epoch, expiresAt: deadline, leaderSource: true)
                guard !stopRequested else { throw CancellationError() }
            }
            self.epoch = epoch; expiresAt = deadline; lastUpload = .distantPast
            status = "Sesi lokasi TL sampai \(deadline.formatted(date: .omitted, time: .standard)); menunggu GPS"
            sensor.start(runID: store.state.runID, epoch: epoch, expiresAt: deadline, background: backgroundEnabled)
        } catch {
            pausePending = true; status = "Start TL belum selesai. Hentikan/retry untuk membersihkan status cloud."
            throw error
        }
    }
    private func schedule(_ sample: LocationSample) {
        guard LocationRules.mayUpload(sample, activeEpoch: epoch, runID: store.state.runID, expiresAt: expiresAt) else { return }
        pending = sample
        guard upload == nil else { return }
        upload = Task { [weak self] in
            guard let self else { return }
            defer { self.upload = nil }
            while let next = self.pending, !Task.isCancelled {
                let delay = max(self.lastUpload.addingTimeInterval(20), self.cloud.retryAfter).timeIntervalSinceNow
                do { try await Task.sleep(for: .seconds(max(0, delay))) } catch { return }
                guard !Task.isCancelled, let sample = self.pending, let deadline = self.expiresAt,
                      LocationRules.mayUpload(sample, activeEpoch: self.epoch, runID: self.store.state.runID, expiresAt: deadline) else { self.pending = nil; return }
                self.pending = nil; self.lastUpload = .now
                for share in self.store.state.leaderShares ?? [] {
                    guard !Task.isCancelled, self.epoch == next.epoch else { return }
                    do { try await self.cloud.upload(sample, ref: share.reference, expiresAt: deadline) }
                    catch { if !Task.isCancelled { self.cloud.note(error); self.status = "Sebagian pengiriman TL gagal; posisi peserta akan menua." }; break }
                }
            }
        }
    }
    func stop() async {
        // Local stop is immediate; cloud pause clears coordinates but retains invitations for resuming.
        stopRequested = true; sensor.stop(); epoch = nil; expiresAt = nil; pending = nil
        upload?.cancel(); let oldUpload = upload; await oldUpload?.value
        guard !busy else { pausePending = true; status = "Sensor TL OFF; tunggu operasi lalu ulangi hentikan untuk konfirmasi cloud."; return }
        busy = true; pausePending = true; defer { busy = false }
        var failed = false
        for share in store.state.leaderShares ?? [] {
            do { try await cloud.pause(share.reference) } catch { failed = true }
        }
        pausePending = failed
        status = failed ? "GPS TL OFF; penghentian cloud belum dikonfirmasi. Retry saat online." : "Lokasi TL dihentikan dan data cloud dibersihkan. Koneksi tetap tersimpan."
        stopRequested = false
    }
    func remove(account: String? = nil) async throws {
        guard !busy, !sensor.running, upload == nil else { throw POCError.message("Hentikan lokasi TL dan tunggu operasi sebelumnya selesai.") }
        busy = true; defer { busy = false }
        let shares = (store.state.leaderShares ?? []).filter { account == nil || $0.accountRecord == account }
        for share in shares {
            try await cloud.revokeAndDelete(share.reference)
            try store.commit { $0.leaderShares?.removeAll { $0.reference == share.reference } }
        }
        if !hasConnections { pausePending = false; stopRequested = false; epoch = nil; expiresAt = nil }
        status = "Koneksi lokasi TL dicabut. Peserta perlu scan ulang agar menerima lokasi TL lagi."
    }
}
