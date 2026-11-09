import Foundation
import Observation
import PreferenceQuality
import TripIntegration

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
    var weatherDiagnosis: [WeatherEvidence] = []
    var exportURLs: [URL] = []
    let catalog: IntegrationCatalog
    let replay: Bool
    let blokM: Bool
    private let pipeline: IntegrationPipeline
    private let store: TripStore
    private var operation: Task<Void, Never>?
    private var epoch = OperationEpoch()
    private var generation: UUID { epoch.current }
    private var loaded = false
    private var evaluationNow: Date {
        guard replay else { return .now }
        let clock = blokM ? BlokMExperiment.snapshotClock(catalog) : TripClock.date("2026-11-05T07:00:00Z")
        return request.effectiveTransport == .transjakartaBRT ? max(clock, (try? BuswayFeed.load().source.checkedAt.addingTimeInterval(1)) ?? clock) : clock
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

    init() {
        do {
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                let isBusway = arguments.contains("--p3-busway") || arguments.contains("--p3-busway-replay")
                let isBlokM = isBusway || arguments.contains("--p3-blok-m") || arguments.contains("--p3-blok-m-replay")
                let isReplay = arguments.contains("--p3-replay") || arguments.contains("--p3-blok-m-replay") || arguments.contains("--p3-busway-replay")
                guard !(arguments.contains("--p3-replay") && isBlokM) else {
                    throw IntegrationError.invalid("Choose one explicit experiment mode.")
                }
                let loadedCatalog = try IntegrationCatalog.load(blokM: isBlokM)
                let service: IntegrationPipeline
                if isReplay {
                    service = isBlokM ? try BlokMReplay.pipeline() : try IntegrationReplay.pipeline()
                } else {
                    let logs = isBlokM ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("C67BlokM-2026-11-06/ProviderLogs") : nil
                    service = IntegrationPipeline(catalog: loadedCatalog, logDirectory: logs)
                }
            #else
                let isBusway = false
                let isBlokM = false
                let isReplay = false
                let loadedCatalog = try IntegrationCatalog.load()
                let service = IntegrationPipeline(catalog: loadedCatalog)
            #endif
            catalog = loadedCatalog; replay = isReplay; blokM = isBlokM; pipeline = service
            let directory: URL?
            if isReplay {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("C67P3Replay-\(UUID())")
            } else if isBusway {
                directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("C67Busway-2026-11-06")
            } else if isBlokM {
                directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("C67BlokM-2026-11-06")
            } else {
                directory = nil
            }
            store = TripStore(directory: directory)
            #if DEBUG
                if isReplay { request = isBlokM ? try BlokMReplay.request() : IntegrationReplay.request() }
                if isBusway { request.transport = .transjakartaBRT }
            #endif
        } catch { fatalError("Invalid bundled catalog: \(error)") }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
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
        error = nil; progress = "Input berubah. Hasil lama tersimpan; buat usulan baru untuk input ini."
    }
    func cancel() {
        epoch.invalidate(); operation?.cancel(); operation = nil
        pipeline.cancel(); busy = false
    }
    private func launch(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        cancel(); error = nil; busy = true
        let token = generation
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await work(token) }
            catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { busy = false; operation = nil }
        }
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
        guard request.requiredCandidateIDs.contains(id) == false else { return }
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
