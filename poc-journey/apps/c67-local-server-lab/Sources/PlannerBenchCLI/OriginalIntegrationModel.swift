import Foundation
import Observation
import PreferenceQuality
import TripIntegration

enum SimpleTripStep: Equatable {
    case idle, recommending, checkingLocations, needsPlaces, needsLocations, planning, finished

    var isProcessing: Bool {
        self == .recommending || self == .checkingLocations || self == .planning
    }
    var title: String {
        switch self {
        case .recommending: "Memilih tempat untuk Anda"
        case .checkingLocations: "Memeriksa lokasi tempat"
        case .planning: "Menyusun jadwal perjalanan"
        case .needsPlaces: "Ada pilihan yang perlu ditinjau"
        case .needsLocations: "Pastikan cabang yang dimaksud"
        case .finished: "Itinerary siap ditinjau"
        case .idle: "Siap membuat itinerary"
        }
    }
}

@MainActor @Observable final class IntegrationModel {
    var request = TripRequest()
    var review: RecommendationReview?
    var selected = Set<String>()
    var prepared: PreparedTrip?
    var session = IntegrationSession()
    var busy = false
    var saving = false
    var progress = "Belum ada permintaan provider."
    var error: String?
    var persistenceWarning: String?
    var simpleStep: SimpleTripStep = .idle
    var simpleResultID: UUID?
    var weatherDiagnosis: [WeatherEvidence] = []
    var exportURLs: [URL] = []
    let catalog: IntegrationCatalog
    let replay: Bool
    private let pipeline: IntegrationPipeline
    private let store: TripStore
    private var operation: Task<Void, Never>?
    private var epoch = OperationEpoch()
    private var generation: UUID { epoch.current }
    private var loaded = false
    private var loading = false
    var isLoaded: Bool { loaded }
    private var injectedClock: (@MainActor () -> Date)?
    private var evaluationNow: Date {
        injectedClock?() ?? (replay ? TripClock.date("2026-11-05T07:00:00Z") : .now)
    }
    var displayPlan: IntegratedPlan? { session.proposal ?? session.accepted }
    var canApplyProposal: Bool {
        guard let proposal = session.proposal, let prepared,
              proposal.request == request, prepared.request == request,
              Set(proposal.prepared.selectedIDs) == selected,
              prepared.locations.count == proposal.prepared.locations.count else { return false }
        return prepared.locations.allSatisfy { location in
            proposal.prepared.locations.first { $0.id == location.id }?.selected == location.selected
        }
    }
    var proposalAcceptanceIssue: String? {
        guard let proposal = session.proposal else { return nil }
        if !proposal.feasible { return "Jadwal masih memiliki konflik. Sesuaikan sebelum digunakan." }
        if !canApplyProposal { return "Input sudah berubah. Buat usulan baru sebelum menggunakan draf ini." }
        if proposal.baseAcceptedID != session.accepted?.id {
            return "Versi itinerary tersimpan sudah berubah. Hitung usulan baru."
        }
        let now = evaluationNow
        if proposal.request.departure < now || now.timeIntervalSince(proposal.createdAt) >= 900
            || proposal.createdAt > now.addingTimeInterval(300) {
            return "Draf sudah lama atau waktu berangkat telah lewat. Sesuaikan dan hitung ulang."
        }
        return nil
    }

    init() {
        do {
            let loadedCatalog = try IntegrationCatalog.load()
            #if DEBUG
                let isReplay = ProcessInfo.processInfo.arguments.contains("--p3-replay")
                let service = isReplay ? try IntegrationReplay.pipeline() : IntegrationPipeline(catalog: loadedCatalog)
            #else
                let isReplay = false
                let service = IntegrationPipeline(catalog: loadedCatalog)
            #endif
            catalog = loadedCatalog; replay = isReplay; pipeline = service
            store = TripStore(directory: isReplay ? FileManager.default.temporaryDirectory
                .appendingPathComponent("C67P3Replay-\(UUID().uuidString)") : nil)
            #if DEBUG
                if isReplay { request = IntegrationReplay.request() }
            #endif
        } catch { fatalError("Invalid bundled catalog: \(error)") }
    }

    // Explicit injection for isolated app-flow regression tests. Normal launch uses init().
    init(catalog: IntegrationCatalog, pipeline: IntegrationPipeline, store: TripStore,
         request: TripRequest, replay: Bool, clock: @escaping @MainActor () -> Date) {
        self.catalog = catalog; self.pipeline = pipeline; self.store = store
        self.request = request; self.replay = replay; self.injectedClock = clock
    }
    func load() async {
        guard !loaded, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let value = try await store.load()
            session = value.session; persistenceWarning = value.warnings.joined(separator: "\n")
            if let plan = displayPlan {
                request = plan.request; prepared = plan.prepared; selected = Set(plan.prepared.selectedIDs)
            }
        } catch { self.error = "Penyimpanan: \(error.localizedDescription)" }
    }
    func edit(_ change: (inout TripRequest) -> Void) {
        guard !saving else { return }
        cancel()
        change(&request); request.revision += 1
        review = nil; prepared = nil; selected = []; exportURLs = []
        simpleStep = .idle; simpleResultID = nil
        error = nil; progress = "Input berubah. Hasil lama tersimpan; buat usulan baru untuk input ini."
    }
    func cancel() {
        let wasProcessing = simpleStep.isProcessing
        epoch.invalidate(); operation?.cancel(); operation = nil
        pipeline.cancel(); busy = false
        if wasProcessing {
            simpleStep = .idle
            progress = "Penyusunan dibatalkan. Itinerary tersimpan tetap tersedia."
        }
    }
    private func launch(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        cancel(); error = nil; busy = true
        let token = generation
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await work(token) }
            catch is CancellationError {
                if generation == token, simpleStep.isProcessing {
                    simpleStep = .idle
                    progress = "Penyusunan dibatalkan. Anda dapat mencobanya kembali."
                }
            }
            catch {
                if generation == token {
                    self.error = error.localizedDescription
                    if simpleStep.isProcessing { simpleStep = .idle }
                }
            }
            if generation == token { busy = false; operation = nil }
        }
    }

    // One operation epoch spans the entire simple flow. Manual lab actions remain separate.
    func createItinerary() {
        guard loaded, !busy, !saving else { return }
        let input = request
        let baseID = session.accepted?.id
        launch { [self] token in
            simpleResultID = nil
            review = nil; prepared = nil; selected = []; exportURLs = []
            simpleStep = .recommending
            progress = "Memilih tempat berdasarkan minat dan jam layanan."
            let value = try await pipeline.recommend(input, now: evaluationNow) { [weak self] message in
                await self?.showProgress(message, token: token)
            }
            guard generation == token, !Task.isCancelled else { return }
            review = value
            selected = Set(input.requiredCandidateIDs + value.suggestions.filter(\.recommended).map(\.id))
            // A smaller result needs consent; hard requirements never disappear automatically.
            guard simpleSelectionIsReady(value) else { return }
            try await prepareSimpleTrip(value, baseID: baseID, token: token)
        }
    }

    private func simpleSelectionIsReady(_ value: RecommendationReview) -> Bool {
        let chosen = value.suggestions.filter { selected.contains($0.id) }
        let uniqueVenues = Set(chosen.map(\.venueID))
        let target = max(value.request.desiredCount, value.request.requiredCandidateIDs.count)
        guard (1 ... 6).contains(selected.count), chosen.count == selected.count,
              selected.count >= target, uniqueVenues.count == chosen.count,
              Set(value.request.requiredCandidateIDs).isSubset(of: selected),
              chosen.allSatisfy(\.selectable) else {
            simpleStep = .needsPlaces
            progress = "Periksa tempat yang tersedia. Pilihan wajib tetap dipertahankan."
            return false
        }
        return true
    }

    func continueWithSelectedPlaces() {
        guard loaded, !saving, !busy, let review, review.request == request else { return }
        let chosen = review.suggestions.filter { selected.contains($0.id) }
        guard (1 ... 6).contains(selected.count), chosen.count == selected.count,
              Set(request.requiredCandidateIDs).isSubset(of: selected), chosen.allSatisfy(\.selectable),
              Set(chosen.map(\.venueID)).count == chosen.count else {
            error = "Pilih 1–6 tempat yang mempunyai fakta dan jam layanan. Tujuan wajib perlu diperbaiki melalui pengaturan."
            return
        }
        let baseID = session.accepted?.id
        launch { [self] token in try await prepareSimpleTrip(review, baseID: baseID, token: token) }
    }

    private func prepareSimpleTrip(_ review: RecommendationReview, baseID: UUID?, token: UUID) async throws {
        simpleStep = .checkingLocations
        progress = "Mencocokkan nama dan cabang tempat."
        let ids = review.suggestions.filter { selected.contains($0.id) }.map(\.id)
        let value = try await pipeline.prepare(review, selectedIDs: ids, now: evaluationNow) { [weak self] message in
            self?.showProgress(message, token: token)
        }
        guard generation == token, !Task.isCancelled else { return }
        prepared = value
        guard value.ready else {
            simpleStep = .needsLocations
            progress = "Ada lokasi yang belum dapat dipastikan. Pilihan tempat tidak diganti."
            return
        }
        try await finishSimpleTrip(value, review: review, baseID: baseID, token: token)
    }

    func continueWithConfirmedLocations() {
        guard loaded, !saving, !busy, let prepared, prepared.ready, let review,
              prepared.request == request, review.request == request else { return }
        let baseID = session.accepted?.id
        launch { [self] token in
            try await finishSimpleTrip(prepared, review: review, baseID: baseID, token: token)
        }
    }

    private func finishSimpleTrip(_ prepared: PreparedTrip, review: RecommendationReview,
                                  baseID: UUID?, token: UUID) async throws {
        simpleStep = .planning
        progress = "Memeriksa waktu kunjungan, perjalanan dan cuaca."
        let value = try await pipeline.plan(prepared, review: review, baseAcceptedID: baseID,
                                            now: evaluationNow) { [weak self] message in self?.showProgress(message, token: token) }
        guard generation == token, !Task.isCancelled else { return }
        var next = session
        next.proposal = value
        // A save cannot be interrupted by an input edit and later restore a stale proposal.
        saving = true
        defer { saving = false }
        try await store.save(next)
        guard generation == token, !Task.isCancelled else { return }
        session = next
        simpleStep = .finished
        simpleResultID = value.id
        progress = value.feasible ? "Itinerary siap ditinjau." : "Jadwal perlu penyesuaian; semua pilihan tetap terlihat."
    }

    func reviseItinerary(_ plan: IntegratedPlan, request updated: TripRequest) {
        guard !busy, !saving, self.plan(withID: plan.id) != nil else { return }
        edit { input in
            input = updated
            input.id = UUID()
        }
        createItinerary()
    }

    func extendAutomatically(_ stop: PlannedStop, plan: IntegratedPlan) {
        let duration = plan.request.duration(stop.venueID) + 30
        guard duration <= 360 else { error = "Durasi maksimum 360 menit."; return }
        var updated = plan.request
        updated.durationByVenue[stop.venueID] = duration
        updated.requiredCandidateIDs = plan.prepared.selectedIDs
        updated.desiredCount = plan.prepared.selectedIDs.count
        reviseItinerary(plan, request: updated)
    }

    func plan(withID id: UUID) -> IntegratedPlan? {
        if session.proposal?.id == id { return session.proposal }
        if session.accepted?.id == id { return session.accepted }
        return nil
    }
    func recommend() {
        let input = request
        launch { [self] token in
            progress = "Menyaring bukti preferensi dan jam layanan…"
            let value = try await pipeline.recommend(input, now: evaluationNow) { [weak self] message in
                await self?.showProgress(message, token: token)
            }
            guard generation == token, !Task.isCancelled else { return }
            review = value
            selected = Set(input.requiredCandidateIDs + value.suggestions.filter(\.recommended).map(\.id))
            prepared = nil; progress = "Tinjau pilihan tempat, lalu verifikasi lokasi."
        }
    }
    private func showProgress(_ value: String, token: UUID) {
        if generation == token { progress = value }
    }
    func setSelected(_ id: String, enabled: Bool) {
        guard !saving, !busy, request.requiredCandidateIDs.contains(id) == false else { return }
        cancel(); prepared = nil
        if enabled { selected.insert(id) } else { selected.remove(id) }
    }
    func verifyLocations() {
        guard let review else { return }
        let ids = review.suggestions.filter { selected.contains($0.id) }.map(\.id)
        launch { [self] token in
            let value = try await pipeline.prepare(review, selectedIDs: ids, now: evaluationNow) { message in
                if generation == token { progress = message }
            }
            guard generation == token, !Task.isCancelled else { return }
            prepared = value; progress = value.ready ? "Lokasi siap; lanjutkan perhitungan jadwal." : "Pilih cabang/lokasi yang belum pasti."
        }
    }
    func choosePin(_ pinID: String, locationID: String) {
        guard !saving, !busy else { return }
        do { try prepared?.choose(pinID, for: locationID) } catch { self.error = error.localizedDescription }
    }
    func plan() {
        guard let review, let prepared else { return }
        let baseID = session.accepted?.id
        launch { [self] token in
            let value = try await pipeline.plan(prepared, review: review, baseAcceptedID: baseID,
                                                now: evaluationNow) { message in if generation == token { progress = message } }
            guard generation == token, !Task.isCancelled else { return }
            var next = session; next.proposal = value
            try await store.save(next)
            guard generation == token, !Task.isCancelled else { return }
            session = next; progress = "Usulan selesai; periksa konflik dan sumber sebelum menerapkan."
        }
    }
    func apply() {
        guard !busy, !saving else { return }
        if let issue = proposalAcceptanceIssue { error = issue; return }
        guard canApplyProposal else { error = "Input atau pilihan tempat berubah. Hitung usulan baru sebelum menerapkan."; return }
        launch { [self] token in
            saving = true; defer { saving = false }
            var next = session; try next.apply(now: evaluationNow)
            try await store.save(next)
            guard generation == token else { return }
            session = next; progress = "Jadwal disimpan sebagai versi yang diterima."
        }
    }
    func reject() {
        launch { [self] token in
            saving = true; defer { saving = false }
            var next = session; next.proposal = nil
            try await store.save(next)
            guard generation == token else { return }
            session = next; progress = "Usulan ditolak; jadwal yang diterima tetap tersimpan."
        }
    }
    func extend(_ stop: PlannedStop, plan: IntegratedPlan) {
        let duration = plan.request.duration(stop.venueID) + 30
        guard duration <= 360 else { error = "Durasi maksimum 360 menit."; return }
        edit { input in
            input = plan.request; input.id = UUID()
            input.durationByVenue[stop.venueID] = duration
            input.requiredCandidateIDs = plan.prepared.selectedIDs
        }
        recommend()
        progress = "Usulan durasi +30 menit. Tinjau tempat lalu hitung ulang seluruh draf; versi diterima tetap disimpan."
    }
    func diagnoseWeather() {
        // A real, isolated WeatherKit request. Never turns on fallback, even when enabled for trip planning.
        launch { [self] token in
            progress = "Diagnosis WeatherKit tanpa fallback…"
            var input = TripRequest(); input.allowOpenMeteo = false
            let pin = PlacePin(id: "diagnosis-hi", name: "Bundaran HI · titik diagnosis", address: "Jakarta",
                               latitude: -6.195, longitude: 106.823)
            let location = LocationReview(id: "diagnosis", query: "Bundaran HI", candidates: [pin], selected: pin)
            let provider = TripWeatherCoordinator()
            let result = try await provider.fetch([location], request: input, now: .now, bypassCache: true)
            guard generation == token, !Task.isCancelled else { return }
            weatherDiagnosis = result
            progress = result.allSatisfy { $0.complete && $0.provider == "weatherkit" }
                ? "Diagnosis WeatherKit menerima data dan atribusi." : "Diagnosis WeatherKit belum berhasil; lihat error provider."
        }
    }
    func export(_ plan: IntegratedPlan) {
        launch { [self] token in
            let folder = try await store.export(plan)
            guard generation == token else { return }
            exportURLs = [folder.appendingPathComponent("experiment.json"), folder.appendingPathComponent("REPORT.md")]
            if plan.rawRoutingReport != nil { exportURLs.append(folder.appendingPathComponent("native-report.json")) }
            if plan.providerLog != nil { exportURLs.append(folder.appendingPathComponent("provider-log.jsonl")) }
        }
    }
}
