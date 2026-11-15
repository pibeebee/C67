import CloudKit
import CoreLocation
import Observation
import SwiftData

@MainActor @Observable final class POCController {
    let store: SessionStore
    let leaderSharing: LeaderLocationSharing
    let planSync: JourneyPlanSync
    private(set) var leaderLocation = ParticipantLocation()
    private var leaderFetchTask: Task<Void, Never>?
    private var leaderFetching = false
    let sensor = LocationService()
    let cloud = CloudLocationChannel()
    let diagnostics = POCDiagnostics()
    let groupRouting = GroupRouteSession()
    let pairing = QRPairingCoordinator()
    private(set) var locations: [String: ParticipantLocation] = [:]
    var error: String?
    private(set) var busy: String?
    private(set) var cloudShare: CKShare?
    private(set) var recipient = "Belum ada penerima yang dikonfirmasi"
    private(set) var recipientAccepted = false
    private(set) var received: LocationSample?
    private(set) var receivedAt: Date?
    private(set) var lastFetchAt: Date?
    private(set) var remoteState = "Belum terhubung"
    private(set) var remoteExpires: Date?
    private(set) var incoming: CloudReference?
    private(set) var uploading = false
    private(set) var sharingStatus = "GPS belum dimulai; tidak otomatis dilanjutkan setelah relaunch"
    var durationMinutes = 30.0
    var backgroundEnabled = true
    private var epoch: UUID?
    private var expiresAt: Date?
    private var uploadTask: Task<Void, Never>?
    private var delayedUpload: Task<Void, Never>?
    private var pendingSample: LocationSample?
    private var lastUpload = Date.distantPast
    private var pollTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var fetching = false
    private var cleanupRequested = false
    private var cleanupInFlight = false
    private var remoteEpoch: UUID?
    private let simEpoch = UUID()

    init(container: ModelContainer, testing: Bool = false) throws {
        var initial = RunState(); if testing { initial.mode = .simulation }
        #if targetEnvironment(simulator)
            initial.mode = .simulation
        #endif
        store = try SessionStore(container: container, initial: initial)
        leaderSharing = LeaderLocationSharing(store: store)
        planSync = JourneyPlanSync(store: store)
        pairing.app = self
        sensor.onEvent = { [weak self] text in self?.diagnostics.log(text) }
        sensor.onSample = { [weak self] sample in self?.schedule(sample) }
        sensor.onExpiration = { [weak self] in
            Task { await self?.stopSharing() }
        }
        if store.state.owner != nil { sharingStatus = "Ada share tersimpan. Sensor OFF. Periksa penerima atau cleanup sebelum memulai ulang." }
    }
    func attempt(_ body: () throws -> Void) {
        do { try body() } catch { self.error = error.localizedDescription }
    }
    func perform(_ label: String, _ body: () async throws -> Void) async {
        guard busy == nil, !cleanupInFlight else { error = "Tunggu operasi sebelumnya selesai."; return }
        busy = label
        do { try await body() } catch { self.error = error.localizedDescription; diagnostics.log("\(label) gagal; \((error as NSError).domain) code=\((error as NSError).code)") }
        busy = nil
        if cleanupRequested { await stopSharing() }
    }
    func resetRun(mode: RunMode) throws {
        guard canReplaceRun else {
            throw POCError.message("Stop/cleanup sharing dan putuskan share TL dahulu sebelum membuat run baru.")
        }
        try store.commit { $0 = RunState(mode: mode) }
        clearReceived(); cloudShare = nil; recipientAccepted = false; diagnostics.reset(); cleanupRequested = false
    }
    var canReplaceRun: Bool {
        !planSync.publishing && !planSync.fetching && !sensor.running && !leaderSharing.locked && !leaderSharing.hasConnections && store.state.leaderBinding == nil && store.state.owner == nil && store.state.cloudBindings.isEmpty && incoming == nil
            && busy == nil && !uploading && !cleanupInFlight && !fetching && !pairing.nearby.active && !pairing.hasPendingCloudWork
    }
    func loadDemo(_ scenario: DemoScenario) throws {
        guard canReplaceRun else { throw POCError.message("Hentikan GPS, cleanup share peserta, dan putuskan undangan/binding TL sebelum membuka demo.") }
        let run = try scenario.run()
        // One transaction, preserving the prior run if fixture creation or persistence fails.
        try store.commit { $0 = run }
        clearReceived(); cloudShare = nil; recipientAccepted = false; error = nil
        cleanupRequested = false
        diagnostics.reset(); diagnostics.log("SIMULASI skenario: \(scenario.rawValue)")
        switch scenario {
        case .start: break
        case .regroup: simulate("jauh")
        case .stale: simulate("stale")
        case .reviewed: simulate("dekat")
        }
    }
    func createQRJourney(journey: String, leader: String) throws {
        let journey = journey.trimmingCharacters(in: .whitespacesAndNewlines)
        let leader = leader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canReplaceRun, !journey.isEmpty, journey.count <= 60, !leader.isEmpty, leader.count <= 40 else { throw POCError.message("Isi nama perjalanan/TL dan cleanup koneksi lama dahulu.") }
        var run = RunState(mode: .real)
        run.qrMembers = []; run.qrJourneyName = journey; run.qrLeaderName = leader
        run.sessions[0].participants = []
        try store.commit { $0 = run }; clearReceived(); cloudShare = nil; recipientAccepted = false; cleanupRequested = false; diagnostics.reset()
    }
    func joinQR(_ invite: JourneyInvite, name: String) throws {
        guard canReplaceRun else { throw POCError.message("Cleanup koneksi lama sebelum bergabung.") }
        var run = RunState(runID: invite.runID, mode: .real)
        run.sessions[0].participants = []
        run.joinedQR = JoinedJourney(journey: invite.journey, leader: invite.leader, leaderRecord: invite.leaderRecord, participantID: "", participantName: name)
        try store.commit { $0 = run }; clearReceived(); cloudShare = nil; recipientAccepted = false; cleanupRequested = false; diagnostics.reset()
    }
    func sample(for id: String) -> LocationSample? {
        if store.state.mode == .simulation { return locations[id]?.sample ?? (id == "P01" ? received : nil) }
        return locations[id]?.displayable(runID: store.state.runID)
    }
    func selectLocation(_ id: String) {
        guard let ref = store.state.cloudBindings.first(where: { $0.participantID == id }) else { return }
        let changed = store.state.binding != ref
        attempt { try store.commit { $0.binding = ref } }
        if changed, store.state.binding == ref { diagnostics.reset() }
        syncSelectedLocation()
    }
    private func syncSelectedLocation() {
        guard let id = store.state.binding?.participantID else { received = nil; receivedAt = nil; remoteExpires = nil; remoteState = "Belum terhubung"; return }
        let location = locations[id]
        received = location?.sample; receivedAt = location?.receivedAt; remoteExpires = location?.expiresAt
        remoteState = location?.status ?? "Terhubung; menunggu lokasi peserta"
    }
    func joinRun(_ text: String) throws {
        guard let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw POCError.message("Run ID harus UUID lengkap dari iPhone TL.") }
        guard store.state.mode == .real else { throw POCError.message("Buat run Perangkat nyata terlebih dahulu.") }
        guard canReplaceRun else { throw POCError.message("Cleanup/putuskan share dahulu sebelum mengganti run.") }
        try store.commit { $0 = RunState(runID: id) }
        clearReceived(); diagnostics.reset()
    }
    func prepare(participantID: String) async {
        await perform("Siapkan share") {
            guard self.store.state.mode == .real, !self.store.state.ended else { throw POCError.message("Sharing hanya tersedia pada run perangkat nyata yang aktif.") }
            try self.cloud.available()
            if let ref = self.store.state.owner {
                let info = try await self.cloud.ownerShare(ref)
                self.cloudShare = info.share; self.recipient = info.recipient; self.recipientAccepted = info.accepted
                return
            }
            let ref = self.cloud.makeReference(runID: self.store.state.runID, participantID: participantID)
            // Persist cleanup information BEFORE any cloud writes, including partial prepare failures.
            try self.store.commit { $0.owner = ref }
            self.cloudShare = try await self.cloud.prepare(ref)
            self.sharingStatus = "Share siap; undang satu TL dengan read-only, lalu periksa penerima"
        }
    }
    func checkRecipient() async {
        await perform("Periksa penerima") {
            guard let ref = self.store.state.owner else { throw POCError.message("Siapkan share terlebih dahulu.") }
            let result = try await self.cloud.ownerShare(ref)
            self.cloudShare = result.share; self.recipient = result.recipient; self.recipientAccepted = result.accepted
            self.sharingStatus = result.accepted ? "TL menerima undangan. Start masih memerlukan persetujuan Anda." : "Menunggu TL menerima undangan"
        }
    }
    func startSharing(consent: Bool) async {
        await perform("Mulai berbagi") {
            guard consent, self.recipientAccepted, self.store.state.mode == .real, let ref = self.store.state.owner,
                  !self.sensor.running, !self.leaderSharing.sensor.running, !self.uploading, !self.store.state.ended else {
                throw POCError.message("Konfirmasi penerima dan persetujuan, lalu tunggu operasi lama selesai.")
            }
            let epoch = UUID(), deadline = Date.now.addingTimeInterval(self.durationMinutes * 60)
            try await self.cloud.begin(ref, epoch: epoch, expiresAt: deadline)
            guard !self.cleanupRequested, self.store.state.owner == ref else { throw POCError.message("Start dibatalkan karena Stop/cleanup diminta.") }
            self.epoch = epoch; self.expiresAt = deadline; self.lastUpload = .distantPast
            self.sharingStatus = "Berbagi aktif sampai \(deadline.formatted(date: .omitted, time: .standard))"
            self.sensor.start(runID: ref.runID, epoch: epoch, expiresAt: deadline, background: self.backgroundEnabled)
        }
    }
    private func schedule(_ sample: LocationSample) {
        guard LocationRules.mayUpload(sample, activeEpoch: epoch, runID: store.state.runID, expiresAt: expiresAt) else { return }
        pendingSample = sample // Replace, never keep an offline route queue.
        guard !uploading, delayedUpload == nil else { return }
        let deadline = max(lastUpload.addingTimeInterval(20), cloud.retryAfter)
        delayedUpload = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard let self else { return }; self.delayedUpload = nil; self.sendPending()
        }
    }
    private func sendPending() {
        guard !uploading, let sample = pendingSample, let ref = store.state.owner, let expiry = expiresAt,
              LocationRules.mayUpload(sample, activeEpoch: epoch, runID: store.state.runID, expiresAt: expiry) else { pendingSample = nil; return }
        pendingSample = nil; uploading = true; lastUpload = .now
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await self.cloud.upload(sample, ref: ref, expiresAt: expiry)
                if self.epoch == sample.epoch { self.sharingStatus = "Upload sequence \(sample.sequence) berhasil; GPS tetap best effort" }
                self.diagnostics.log("upload success sequence=\(sample.sequence)")
            } catch {
                if !Task.isCancelled { self.cloud.note(error); self.sharingStatus = "Upload gagal; posisi TL akan menua. \(self.cloud.lastError ?? "")"; self.diagnostics.log("upload error; \(self.cloud.lastError ?? "unknown")") }
            }
            self.uploading = false; self.uploadTask = nil
            if let next = self.pendingSample { self.schedule(next) }
        }
    }
    func stopSharing() async {
        pairing.stop()
        sensor.stop(); epoch = nil; expiresAt = nil; pendingSample = nil
        cleanupRequested = true
        delayedUpload?.cancel(); delayedUpload = nil; uploadTask?.cancel()
        sharingStatus = "Pengiriman lokal dihentikan. Pencabutan cloud belum dikonfirmasi."
        diagnostics.log("Stop lokal; upload task cancelled; cloud cleanup pending")
        // Wait for bootstrap writes before zone deletion, so a late prepare cannot recreate a revoked zone.
        await pairing.finishCloudWork()
        guard busy == nil, !cleanupInFlight else { return }
        guard let ref = store.state.owner else {
            await leaveLeaderLocation()
            cleanupRequested = false; sharingStatus = "Sensor dan pengiriman lokal OFF"; return
        }
        cleanupInFlight = true; defer { cleanupInFlight = false }
        // Revoke the entire private zone; in-flight writes cannot recreate a deleted zone.
        do {
            try await cloud.revokeAndDelete(ref)
            try store.commit { next in if next.owner == ref { next.owner = nil } }
            cloudShare = nil; recipientAccepted = false
            await leaveLeaderLocation()
            cleanupRequested = false
            sharingStatus = "Pengiriman OFF; cloud cleanup dikonfirmasi. Screenshot/ekspor eksternal tidak dihapus."
            diagnostics.log("cloud cleanup acknowledged")
        } catch {
            sharingStatus = "Pengiriman OFF di perangkat ini; pencabutan cloud belum dikonfirmasi. Retry cleanup ketika online."
            self.error = error.localizedDescription; diagnostics.log("cloud cleanup pending")
        }
    }
    func accept(_ metadata: CKShare.Metadata) async {
        await perform("Terima undangan") {
            guard self.store.state.mode == .real, !self.store.state.ended,
                  self.store.state.cloudBindings.isEmpty, self.incoming == nil, !self.pairing.nearby.active else { throw POCError.message("Pilih run nyata yang aktif dan putuskan undangan/binding lama sebelum menerima share lain.") }
            self.incoming = try await self.cloud.accept(metadata)
            self.clearReceived()
        }
    }
    func acceptURL(_ text: String) async {
        await perform("Baca URL undangan") {
            guard self.store.state.cloudBindings.isEmpty, self.incoming == nil, !self.pairing.nearby.active else { throw POCError.message("Putuskan undangan/binding lama terlebih dahulu.") }
            let metadata = try await self.cloud.metadata(for: text)
            guard self.store.state.mode == .real, !self.store.state.ended else { throw POCError.message("Pilih run perangkat nyata yang aktif.") }
            self.incoming = try await self.cloud.accept(metadata)
        }
    }
    func bindIncoming() throws {
        guard let ref = incoming, ref.runID == store.state.runID, Participant.fixture.contains(where: { $0.id == ref.participantID }),
              !store.state.ended, store.state.binding == nil else { throw POCError.message("Run ID/ID peserta tidak cocok, run berakhir, atau masih ada binding lama. Putuskan share lama terlebih dahulu.") }
        try store.commit { $0.binding = ref }
        incoming = nil; clearReceived(); remoteState = "Terhubung; menunggu peserta Start"
    }
    func leaveShare(participantID: String? = nil) async {
        await perform("Putuskan share") {
            let ref = participantID.flatMap { id in self.store.state.cloudBindings.first { $0.participantID == id } } ?? self.store.state.binding ?? self.incoming
            guard let ref else { return }
            if let account = self.store.state.qrMembers?.first(where: { $0.reference == ref })?.accountRecord {
                try await self.leaderSharing.remove(account: account)
            }
            try await self.cloud.leave(ref)
            try self.store.commit { next in
                next.qrMembers?.removeAll { $0.reference == ref }
                if next.binding == ref { next.binding = next.qrMembers?.first?.reference }
            }
            self.incoming = nil; self.locations[ref.participantID] = nil; self.syncSelectedLocation()
        }
    }
    func fetch() async {
        guard !fetching, !store.state.ended, store.state.mode == .real else { return }
        let refs = store.state.cloudBindings
        guard !refs.isEmpty else { return }
        fetching = true; defer { fetching = false; syncSelectedLocation() }
        for ref in refs {
            guard !Task.isCancelled, ref.runID == store.state.runID else { return }
            do {
                let result = try await cloud.fetch(ref)
                guard store.state.cloudBindings.contains(ref), !store.state.ended, !Task.isCancelled else { continue }
                var location = locations[ref.participantID] ?? ParticipantLocation()
                lastFetchAt = .now
                if location.epoch != result.epoch { location.sample = nil; location.receivedAt = nil; location.epoch = result.epoch }
                location.expiresAt = result.expiresAt
                if result.state != "active" || Date.now >= result.expiresAt {
                    location.sample = nil; location.receivedAt = nil
                    location.status = result.state == "ready" ? "Menunggu peserta Start" : "Sesi berbagi berakhir"
                } else {
                    location.status = "Sharing aktif; lihat umur sampel"
                    if let sample = result.sample, let epoch = result.epoch,
                       LocationRules.canReplace(sample, old: location.sample, runID: ref.runID, epoch: epoch) {
                        location.sample = sample; location.receivedAt = .now
                        if store.state.binding == ref { diagnostics.received(sample) }
                    }
                }
                locations[ref.participantID] = location
            } catch {
                if let ck = error as? CKError, [.zoneNotFound, .unknownItem, .permissionFailure].contains(ck.code) {
                    locations[ref.participantID] = ParticipantLocation(status: "Share dicabut/tidak dapat diakses. Hubungkan ulang bila perlu.")
                } else {
                    cloud.note(error)
                    var location = locations[ref.participantID] ?? ParticipantLocation()
                    location.status = "Fetch gagal. Lihat umur posisi terakhir."; locations[ref.participantID] = location
                    break // Respect CloudKit retry-after across the whole group.
                }
            }
        }
    }
    func leaveLeaderLocation() async {
        guard let ref = store.state.leaderBinding else { return }
        do {
            try await cloud.leave(ref)
            try store.commit { if $0.leaderBinding == ref { $0.leaderBinding = nil } }
            leaderLocation = ParticipantLocation(status: "Koneksi lokasi TL diputus")
        } catch { self.error = "Lokasi lokal OFF; keluar dari share TL belum dikonfirmasi. Coba berhenti lagi saat online." }
    }
    func fetchLeaderLocation() async {
        guard !leaderFetching, !store.state.ended, store.state.mode == .real, let ref = store.state.leaderBinding else { return }
        leaderFetching = true; defer { leaderFetching = false }
        do {
            let result = try await cloud.fetch(ref)
            guard store.state.leaderBinding == ref, !Task.isCancelled else { return }
            leaderLocation = leaderLocation.applying(result, runID: ref.runID)
        } catch {
            if let ck = error as? CKError, [.zoneNotFound, .unknownItem, .permissionFailure].contains(ck.code) {
                leaderLocation = ParticipantLocation(status: "Lokasi TL tidak dapat diakses. Hubungkan ulang lewat QR.")
            } else { cloud.note(error); leaderLocation.status = "Fetch TL gagal; lihat umur posisi terakhir." }
        }
    }
    func setParticipantVisible(_ active: Bool) {
        leaderFetchTask?.cancel(); leaderFetchTask = nil
        guard active, !store.state.ended else { return }
        leaderFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.planSync.fetch()
                await self.fetchLeaderLocation()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
    func setLeaderVisible(_ active: Bool) {
        pollTask?.cancel(); pollTask = nil
        observationTask?.cancel(); observationTask = nil
        guard active, !store.state.ended else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.planSync.publish()
                await self.fetch()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let validLease = self.store.state.mode == .simulation || (self.remoteExpires.map { $0 > .now } ?? false)
                self.diagnostics.observe(validLease ? self.received : nil)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    func clearReceived() { leaderLocation = ParticipantLocation(); locations.removeAll(); received = nil; receivedAt = nil; lastFetchAt = nil; remoteEpoch = nil; remoteExpires = nil; remoteState = "Belum ada data" }
    func startLocalSensor() throws {
        guard store.state.mode == .real, store.state.owner == nil, !sensor.running, !leaderSharing.locked, busy == nil else {
            throw POCError.message("Uji lokal memerlukan run nyata tanpa share peserta aktif/tersimpan.")
        }
        epoch = nil; expiresAt = nil // No cloud-upload lease; every sample fails the upload consent guard.
        sharingStatus = "UJI SENSOR LOKAL — tidak dikirim ke CloudKit/TL"
        sensor.start(runID: store.state.runID, epoch: UUID(), expiresAt: .now.addingTimeInterval(durationMinutes * 60), background: backgroundEnabled)
    }
    func simulate(_ kind: String) {
        guard store.state.mode == .simulation else { error = "Sampel sintetis hanya untuk mode Simulasi."; return }
        var sample = LocationSample(runID: store.state.runID, epoch: simEpoch, sequence: (received?.sequence ?? 0) + 1,
                                    latitude: store.state.meetingPoint?.latitude ?? -6.1754, longitude: store.state.meetingPoint?.longitude ?? 106.8272,
                                    measuredAt: .now, accuracy: 10, reduced: false, simulated: true)
        if kind == "jauh" { sample.latitude += 0.01 }
        if kind == "stale" { sample.measuredAt = .now.addingTimeInterval(-180) }
        if kind == "reduced" { sample.reduced = true; sample.accuracy = 1000 }
        received = sample; receivedAt = .now; remoteState = "SIMULASI — bukan GPS perangkat"; diagnostics.received(sample)
        for (index, p) in store.state.sessions.last!.participants.enumerated() {
            var item = sample; item.latitude += Double(index) * 0.001; item.longitude += Double(index) * 0.0015
            if index == 2 { item.measuredAt = .now.addingTimeInterval(-180) }
            locations[p.id] = ParticipantLocation(sample: item, receivedAt: .now, expiresAt: .now.addingTimeInterval(3600), epoch: simEpoch, status: "SIMULASI")
        }
        var tl = sample; tl.latitude -= 0.001; tl.longitude += 0.001
        leaderLocation = ParticipantLocation(sample: tl, receivedAt: .now, expiresAt: .now.addingTimeInterval(3600), epoch: simEpoch, status: "SIMULASI TL")
    }
}
