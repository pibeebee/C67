import Foundation
import CryptoKit
import CloudKit
import MultipeerConnectivity
import Observation

@MainActor @Observable final class QRPairingCoordinator {
    weak var app: POCController?
    let nearby = NearbyPairing()
    private(set) var invite: JourneyInvite?
    private(set) var completed = false
    private(set) var working = false
    private var key: Curve25519.Signing.PrivateKey?
    private var hello: PairingHello?
    private var welcome: PairingWelcome?
    private var reservations: [MCPeerID: (PairingHello, PairingWelcome)] = [:]
    private var processing = Set<MCPeerID>()
    private var generation = UUID()
    private var cloudTasks: [UUID: Task<Void, Never>] = [:]
    var hasPendingCloudWork: Bool { !cloudTasks.isEmpty }
    func finishCloudWork() async {
        let tasks = Array(cloudTasks.values)
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    func stop() { completed = false; generation = UUID(); nearby.stop(); reservations.removeAll(); processing.removeAll(); key = nil; invite = nil; hello = nil; welcome = nil; working = false }
    func host() async {
        guard let app, !working else { return }
        stop(); working = true; let current = generation
        defer { if current == generation { working = false } }
        do {
            guard app.store.state.mode == .real, app.store.state.qrMembers != nil, !app.store.state.ended,
                  app.store.state.activeIndex != nil, app.store.state.owner == nil else { throw POCError.message("Buat perjalanan QR dengan sesi aktif terlebih dahulu.") }
            let runID = app.store.state.runID
            let record = try await app.cloud.accountRecordName()
            guard current == generation, app.store.state.runID == runID else { return }
            let key = Curve25519.Signing.PrivateKey(); self.key = key
            let token = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
            let invite = JourneyInvite(runID: runID, journey: app.store.state.qrJourneyName ?? "Perjalanan", leader: app.store.state.qrLeaderName ?? "Tour leader", leaderRecord: record,
                                       token: token, publicKey: key.publicKey.rawRepresentation, expiresAt: .now.addingTimeInterval(300))
            self.invite = invite
            try nearby.start(invite: invite, hosting: true)
            nearby.onMessage = { [weak self] message, peer in self?.receiveHost(message, peer: peer) }
            nearby.onDisconnect = { [weak self] peer in self?.reservations.removeValue(forKey: peer) }
        } catch { app.error = error.localizedDescription }
    }
    func join(_ invite: JourneyInvite, name: String, consent: Bool) async {
        guard let app, !working else { return }
        stop(); completed = false; working = true; let current = generation
        defer { if current == generation { working = false } }
        do {
            try invite.validate()
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard consent, !name.isEmpty, name.count <= 40, app.canReplaceRun else { throw POCError.message("Isi nama dan persetujuan. Cleanup share lama sebelum bergabung.") }
            let record = try await app.cloud.accountRecordName()
            guard record != invite.leaderRecord else { throw POCError.message("Peserta dan TL harus memakai akun iCloud berbeda.") }
            guard current == generation, app.canReplaceRun else { return }
            let hello = PairingHello(challenge: UUID(), accountRecord: record, name: name)
            self.invite = invite; self.hello = hello
            // The explicit join button authorizes replacing this device's local run, not starting tracking silently.
            try app.joinQR(invite, name: name)
            try nearby.start(invite: invite, hosting: false)
            nearby.onConnect = { [weak self] peer in
                do { try self?.nearby.send(PairingEnvelope(kind: .hello, hello: hello), to: peer) }
                catch { self?.app?.error = error.localizedDescription }
            }
            nearby.onMessage = { [weak self] message, peer in self?.receiveGuest(message, peer: peer) }
        } catch { app.error = error.localizedDescription }
    }
    private func receiveHost(_ message: PairingEnvelope, peer: MCPeerID) {
        guard !processing.contains(peer), let app, let invite, let key, invite.expiresAt > .now,
              app.store.state.runID == invite.runID, app.store.state.activeIndex != nil else { return }
        if message.kind == .hello, let hello = message.hello {
            do {
                guard !hello.name.isEmpty, hello.name.count <= 40, !hello.accountRecord.isEmpty,
                      hello.accountRecord.count < 256, hello.accountRecord != invite.leaderRecord,
                      app.store.state.cloudBindings.count + reservations.count < 20 else { throw POCError.message("Nama/akun tidak valid atau kapasitas POC penuh.") }
                if let existing = reservations[peer] {
                    guard existing.0 == hello else { throw POCError.message("Permintaan pairing berubah; scan ulang.") }
                    try nearby.send(PairingEnvelope(kind: .welcome, welcome: existing.1), to: peer); return
                }
                guard !reservations.values.contains(where: { $0.0.accountRecord == hello.accountRecord }) else { throw POCError.message("Akun ini sedang diproses. Tunggu pairing sebelumnya.") }
                let participantID = app.store.state.qrMembers?.first(where: { $0.accountRecord == hello.accountRecord })?.id ?? UUID().uuidString
                processing.insert(peer)
                let current = generation, taskID = UUID()
                cloudTasks[taskID] = Task {
                    defer { self.processing.remove(peer); self.cloudTasks[taskID] = nil }
                    do {
                        let leaderURL = try await app.leaderSharing.ensureRecipient(account: hello.accountRecord)
                        guard current == self.generation, self.nearby.active, invite.expiresAt > .now else { return }
                        var welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: hello.challenge, participantID: participantID, accountRecord: hello.accountRecord, signature: Data(), leaderURL: leaderURL, meetingPoint: app.store.state.meetingPoint)
                        welcome.signature = try key.signature(for: welcome.signedData())
                        self.reservations[peer] = (hello, welcome)
                        try self.nearby.send(PairingEnvelope(kind: .welcome, welcome: welcome), to: peer)
                    } catch { if current == self.generation { self.fail(error, peer: peer) } }
                }
            } catch { fail(error, peer: peer) }
        } else if message.kind == .share, let url = message.url, let reservation = reservations[peer] {
            processing.insert(peer); let current = generation
            let taskID = UUID()
            cloudTasks[taskID] = Task {
                defer { self.processing.remove(peer); self.cloudTasks[taskID] = nil }
                do {
                    let metadata = try await app.cloud.metadata(for: url)
                    guard current == self.generation, self.nearby.active, invite.expiresAt > .now, app.store.state.runID == invite.runID else { return }
                    let ref = try await app.cloud.accept(metadata, expectedRunID: invite.runID, expectedParticipantID: reservation.1.participantID, expectedOwnerRecord: reservation.0.accountRecord)
                    guard current == self.generation, self.nearby.active, invite.expiresAt > .now, app.store.state.runID == invite.runID, app.store.state.activeIndex != nil else {
                        try? await app.cloud.leave(ref); return
                    }
                    do {
                        try app.store.commit { try $0.register(PairedMember(id: reservation.1.participantID, name: reservation.0.name, accountRecord: reservation.0.accountRecord, reference: ref)) }
                    } catch { try? await app.cloud.leave(ref); throw error }
                    var receipt = PairingReceipt(challenge: reservation.1.challenge, participantID: ref.participantID, signature: Data())
                    receipt.signature = try key.signature(for: receipt.signedData())
                    try self.nearby.send(PairingEnvelope(kind: .accepted, receipt: receipt), to: peer)
                    self.reservations.removeValue(forKey: peer)
                    self.nearby.fail("\(reservation.0.name) terhubung. Peserta berikutnya dapat scan QR ini.")
                    await app.fetch()
                } catch { if current == self.generation { self.fail(error, peer: peer) } }
            }
        }
    }
    private func receiveGuest(_ message: PairingEnvelope, peer: MCPeerID) {
        guard let app, let invite, let hello else { return }
        if message.kind == .failure { app.error = "Pairing belum berhasil. Coba ulang; cleanup jika share sudah dibuat."; return }
        if message.kind == .welcome, let welcome = message.welcome, self.welcome == nil, !working {
            working = true; let current = generation
            let taskID = UUID()
            cloudTasks[taskID] = Task {
                defer { self.cloudTasks[taskID] = nil; if current == self.generation { self.working = false } }
                do {
                    try welcome.validate(invite: invite, hello: hello)
                    guard current == self.generation, app.store.state.runID == invite.runID, app.store.state.owner == nil else { return }
                    self.welcome = welcome
                    let ref = app.cloud.makeReference(runID: invite.runID, participantID: welcome.participantID)
                    try app.store.commit {
                        $0.owner = ref; $0.joinedQR?.participantID = welcome.participantID
                        $0.meetingPoint = welcome.meetingPoint
                    }
                    guard let leaderURL = welcome.leaderURL else { throw POCError.message("TL memakai versi pairing lama. Perbarui kedua aplikasi dan scan ulang.") }
                    let leaderMetadata = try await app.cloud.metadata(for: leaderURL)
                    let leaderRef = try await app.cloud.accept(leaderMetadata, expectedRunID: invite.runID, expectedParticipantID: "TL", expectedOwnerRecord: invite.leaderRecord)
                    // Persist accepted read access for cleanup even if the local pairing view was closed.
                    do { try app.store.commit { $0.leaderBinding = leaderRef } }
                    catch { try? await app.cloud.leave(leaderRef); throw error }
                    guard current == self.generation, app.store.state.owner == ref else { return }
                    _ = try await app.cloud.prepare(ref)
                    guard current == self.generation, app.store.state.owner == ref else { return }
                    let share = try await app.cloud.inviteLeader(ref, recordName: invite.leaderRecord)
                    guard current == self.generation, let url = share.url else { return }
                    try self.nearby.send(PairingEnvelope(kind: .share, url: url.absoluteString), to: peer)
                    self.nearby.fail("Menunggu TL menerima akses privat…")
                } catch { if current == self.generation { app.error = error.localizedDescription; self.nearby.fail("Pairing belum selesai. Cleanup share bila perlu sebelum mencoba ulang.") } }
            }
        } else if message.kind == .accepted, let receipt = message.receipt, let welcome, !completed {
            do { try receipt.validate(invite: invite, welcome: welcome) } catch { app.error = error.localizedDescription; return }
            completed = true
            // Pairing has finished; the explicit consent on the join screen authorizes this start.
            nearby.stop(); nearby.fail("Terhubung ke \(invite.leader). Memulai berbagi lokasi…")
            let current = generation
            Task {
                await app.checkRecipient()
                guard current == self.generation, self.completed, app.recipientAccepted else { return }
                await app.startSharing(consent: true)
                await app.planSync.fetch()
            }
        }
    }
    private func fail(_ error: Error, peer: MCPeerID) {
        app?.error = error.localizedDescription
        try? nearby.send(PairingEnvelope(kind: .failure), to: peer)
    }
}
