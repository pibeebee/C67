import Foundation
import Observation
import PreferenceQuality
import TripIntegration

// This app owns presentation flow. Shared packages own recommendation and routing rules.
enum JourneyMode: String, Codable, CaseIterable, Identifiable {
    case demo, live
    var id: String { rawValue }
    var label: String { self == .demo ? "Demo" : "Live" }
}
enum JourneyPhase: String, Codable {
    case home, setup, preferences, places, review, result
    var title: String {
        switch self {
        case .home: "Perjalananmu"
        case .setup: "Atur perjalanan"
        case .preferences: "Apa yang kamu suka?"
        case .places: "Pilih tempatmu"
        case .review: "Siap menjelajah?"
        case .result: "Itinerary kamu"
        }
    }
    var number: Int {
        switch self {
        case .home, .result: 0
        case .setup: 1
        case .preferences: 2
        case .places: 3
        case .review: 4
        }
    }
}

@MainActor @Observable final class JourneyModel {
    private(set) var catalog: IntegrationCatalog
    let geometry: BuswayGeometryCatalog?
    let roadRoutes: JourneyRoadRoutes
    let root: URL
    private(set) var mode: JourneyMode = .demo
    var phase: JourneyPhase = .home
    var request: TripRequest
    var selected = Set<String>()
    var review: RecommendationReview?
    var prepared: PreparedTrip?
    var session = IntegrationSession()
    var busy = false
    var saving = false
    var switching = false
    var draftAvailable = false
    var progress = ""
    var error: String?
    var persistenceWarning: String?
    var exportURLs: [URL] = []
    var diagnosis: [WeatherEvidence] = []
    var originResults: [PlacePin] = []
    var originSearching = false
    var originSearchMessage: String?
    private let originSearch: any TripPlaceSearching
    private var originOperation: Task<Void, Never>?
    private var originSearchID = UUID()
    private var pipeline: IntegrationPipeline
    private var store: TripStore
    private var draftStore: JourneyDraftStore
    private var operation: Task<Void, Never>?
    private var persistence: Task<Void, Never>?
    private var epoch = OperationEpoch()
    private var loaded = false

    var now: Date {
        mode == .demo ? Self.demoClock(catalog) : .now
    }
    var plan: IntegratedPlan? { session.proposal ?? session.accepted }
    var hasDraft: Bool { draftAvailable || review != nil || phase != .home || session.proposal != nil }
    var canApply: Bool {
        guard let proposal = session.proposal, proposal.feasible, proposal.request == request,
              let prepared, prepared.request == request,
              Set(proposal.prepared.selectedIDs) == selected else { return false }
        return prepared.locations.allSatisfy { location in
            proposal.prepared.locations.first { $0.id == location.id }?.selected == location.selected
        }
    }
    var dateRange: ClosedRange<Date> {
        let start = TripClock.calendar.startOfDay(for: now)
        return start ... start.addingTimeInterval(6 * 86400)
    }
    static func demoClock(_ catalog: IntegrationCatalog) -> Date {
        max(BlokMExperiment.snapshotClock(catalog), (try? BuswayFeed.load().source.checkedAt.addingTimeInterval(1)) ?? .distantPast)
    }
    init(root: URL? = nil, originSearch: (any TripPlaceSearching)? = nil) {
        self.originSearch = originSearch ?? MapKitTripSearch(includeAddresses: true)
        do {
            let loadedCatalog = try IntegrationCatalog.load(includeBlokM: true)
            let arguments = ProcessInfo.processInfo.arguments
            let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("C67JourneyShowcase")
            let resolvedRoot: URL
            if root == nil, let index = arguments.firstIndex(of: "--journey-test-id"), arguments.indices.contains(index + 1) {
                resolvedRoot = base.appendingPathComponent("UITests/" + arguments[index + 1])
            } else if root == nil, arguments.contains("--journey-live-check") {
                resolvedRoot = base.appendingPathComponent("LiveChecks/\(UUID())")
            } else { resolvedRoot = base }
            let initialMode: JourneyMode
            let initialPipeline: IntegrationPipeline
            var initialRequest: TripRequest
            initialMode = .demo
            initialPipeline = try BlokMReplay.pipeline(city: true, expanded: true)
            initialRequest = BlokMExperiment.request(now: Self.demoClock(loadedCatalog))
            initialRequest.transport = .transjakartaBRT
            initialRequest.useCityCatalog = true
            initialRequest.useEmbedding = initialMode == .live
            let directory = resolvedRoot.appendingPathComponent(initialMode.rawValue)
            catalog = loadedCatalog; geometry = (try? .load(network: true)) ?? (try? .load()); self.root = resolvedRoot
            roadRoutes = arguments.contains("--journey-test-id") ? .testReplay() : JourneyRoadRoutes()
            mode = initialMode; pipeline = initialPipeline; request = initialRequest
            store = TripStore(directory: directory); draftStore = JourneyDraftStore(directory: directory)
        } catch { fatalError("Invalid bundled journey catalog: \(error)") }
    }
    func load() async {
        guard !loaded else { return }
        loaded = true
        let token = epoch.current
        do {
            let loadedSession = try await store.load()
            let draft = try await draftStore.load()
            guard epoch.isCurrent(token) else { return }
            session = loadedSession.session
            persistenceWarning = loadedSession.warnings.joined(separator: "\n")
            if let draft {
                draftAvailable = true
                try configureCatalog(city: draft.request.useCityCatalog == true)
                guard draft.mode == mode, draft.selected.count <= 6,
                      draft.selected.isSubset(of: Set(catalog.quality.candidates.map(\.id))) else {
                    throw IntegrationError.invalid("Draf tidak sesuai mode/katalog.")
                }
                request = draft.request; selected = draft.selected
                review = draft.review?.request == request ? draft.review : nil
                prepared = draft.prepared?.request == request ? draft.prepared : nil
                phase = .home
            } else if let value = plan {
                try configureCatalog(city: value.request.useCityCatalog == true)
                request = value.request; selected = Set(value.prepared.selectedIDs); prepared = value.prepared
            }
        } catch { self.error = error.localizedDescription }
    }
    private func configureCatalog(city: Bool) throws {
        catalog = try IntegrationCatalog.load(blokM: !city, includeBlokM: city)
        if mode == .demo { pipeline = try BlokMReplay.pipeline(city: city, expanded: city) }
        else { pipeline = IntegrationPipeline(catalog: catalog, logDirectory: root.appendingPathComponent("live/ProviderLogs")) }
    }
    func switchArea(city: Bool) {
        guard !saving else { return }
        cancel()
        do {
            try configureCatalog(city: city)
            edit { input in
                input.useCityCatalog = city
                input.requiredCandidateIDs = []; input.durationByVenue = [:]; input.targetAreas = nil
            }
            session.proposal = nil; persist()
        } catch { self.error = error.localizedDescription }
    }
    func switchMode(_ value: JourneyMode) async {
        guard value != mode, !saving, !switching else { return }
        switching = true; defer { switching = false }
        cancel(); persist()
        await flushDraft()
        mode = value
        try? configureCatalog(city: true)
        let directory = root.appendingPathComponent(value.rawValue)
        store = TripStore(directory: directory); draftStore = JourneyDraftStore(directory: directory)
        request = BlokMExperiment.request(now: now); request.transport = .transjakartaBRT; request.useCityCatalog = true
        request.useEmbedding = value == .live
        selected = []; review = nil; prepared = nil; session = .init(); phase = .home
        draftAvailable = false
        exportURLs = []; diagnosis = []; error = nil; persistenceWarning = nil
        loaded = false
        await load()
    }
    func persist() {
        draftAvailable = true
        let snapshot = JourneyDraft(mode: mode, request: request, phase: phase, selected: selected, review: review, prepared: prepared)
        let destination = draftStore
        let previous = persistence
        let token = epoch.current
        persistence = Task { @MainActor [weak self] in
            await previous?.value
            do { try await destination.save(snapshot) }
            catch { if self?.epoch.isCurrent(token) == true { self?.persistenceWarning = error.localizedDescription } }
        }
    }
    func flushDraft() async { await persistence?.value }
    func cancel() {
        originSearchID = UUID(); originOperation?.cancel(); originOperation = nil; originSearch.cancel()
        originSearching = false; originResults = []; originSearchMessage = nil
        epoch.invalidate(); operation?.cancel(); operation = nil; pipeline.cancel(); busy = false
    }
    func edit(_ change: (inout TripRequest) -> Void) {
        guard !saving else { return }
        cancel(); change(&request); request.revision += 1
        review = nil; prepared = nil; selected = []; exportURLs = []; error = nil
        persist()
    }
    var availableAreas: [TripArea] {
        TripArea.allCases.filter { area in catalog.quality.candidates.contains { area.contains($0.id) } }
    }
    func toggleArea(_ area: TripArea) {
        edit { input in
            var areas = input.targetAreas ?? []
            if areas.contains(area) { areas.removeAll { $0 == area } } else { areas.append(area) }
            input.targetAreas = areas
        }
    }
    func toggleDesiredSpot(_ id: String) {
        guard let candidate = catalog.candidate(id) else { return }
        if !request.requiredCandidateIDs.contains(id), request.requiredCandidateIDs.count >= 6 {
            error = "Maksimal enam spot wajib."; return
        }
        edit { input in
            if input.requiredCandidateIDs.contains(id) { input.requiredCandidateIDs.removeAll { $0 == id } }
            else {
                input.requiredCandidateIDs.removeAll { catalog.candidate($0)?.venueID == candidate.venueID }
                input.requiredCandidateIDs.append(id)
                input.desiredCount = max(input.desiredCount, input.requiredCandidateIDs.count)
            }
        }
    }
    func setOriginQuery(_ query: String) {
        edit { $0.originQuery = query; $0.originPin = nil }
    }
    func chooseOrigin(_ pin: PlacePin) {
        guard IntegrationCatalog.contains(pin), originResults.contains(pin) || (mode == .demo && BlokMReplay.origins.contains(pin)) else { return }
        edit { $0.originQuery = pin.name; $0.originPin = pin }
    }
    func searchOrigin() {
        guard !saving, !switching else { return }
        cancel()
        let query = request.originQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { originSearchMessage = "Ketik minimal tiga karakter."; return }
        if mode == .demo {
            originResults = BlokMReplay.origins.filter {
                PlaceIdentityPolicy.normalize($0.name).contains(PlaceIdentityPolicy.normalize(query))
            }
            originSearchMessage = originResults.isEmpty ? "Tidak ada titik contoh. Pilih contoh di bawah atau gunakan Live untuk pencarian bebas." : "Pilih titik contoh Demo."
            return
        }
        originSearching = true
        let token = UUID(); originSearchID = token
        originOperation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if originSearchID == token { originSearching = false; originOperation = nil } }
            do {
                let results = try await originSearch.search(query: query)
                try Task.checkCancellation()
                guard originSearchID == token else { return }
                originResults = results.filter { IntegrationCatalog.contains($0) }
                originSearchMessage = originResults.isEmpty ? "Tidak ada hasil dalam cakupan Jakarta. Coba nama tempat atau alamat lain." : "Pilih lokasi yang benar dari hasil MapKit."
            } catch {
                guard originSearchID == token, !Task.isCancelled else { return }
                originSearchMessage = "Pencarian gagal: " + ProviderDiagnostics.message(error)
            }
        }
    }
    func newTrip() {
        guard !saving else { return }
        try? configureCatalog(city: true)
        edit { input in
            input = BlokMExperiment.request(now: now)
            input.transport = .transjakartaBRT
            input.useCityCatalog = true
            input.useEmbedding = mode == .live
        }
        session.proposal = nil; phase = .setup; persist()
    }
    func resume() {
        if session.proposal?.request == request { phase = .result }
        else if prepared != nil { phase = .review }
        else if review != nil { phase = .places }
        else { phase = .setup }
    }
    func back() {
        guard !saving else { return }
        cancel()
        switch phase {
        case .setup, .home, .result: phase = .home
        case .preferences: phase = .setup
        case .places: phase = .preferences
        case .review: phase = .places
        }
        persist()
    }
    func advanceToPreferences() {
        do { try request.validate(catalog: catalog, now: now); phase = .preferences; error = nil; persist() }
        catch { self.error = error.localizedDescription }
    }
    var timeBudget: TripTimeBudget {
        TripTimeBudget.evaluate(request, selectedIDs: Array(selected), catalog: catalog)
    }
    func adjustTimeBudget(longerDay: Bool) {
        guard !saving else { return }
        let preserved = selected
        edit { input in
            if longerDay {
                let lastMinute = TripClock.calendar.startOfDay(for: input.departure).addingTimeInterval(86340)
                input.deadline = min(lastMinute, input.deadline.addingTimeInterval(3600))
            } else {
                input.defaultDuration = max(15, input.defaultDuration - 15)
                for (id, duration) in input.durationByVenue { input.durationByVenue[id] = max(15, duration - 15) }
            }
        }
        selected = preserved; phase = .setup; persist()
    }
    private func launch(_ work: @escaping @MainActor (UUID) async throws -> Void) {
        cancel(); busy = true; error = nil
        let token = epoch.current
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await work(token) }
            catch is CancellationError { }
            catch { if epoch.isCurrent(token) { self.error = error.localizedDescription } }
            if epoch.isCurrent(token) { busy = false; operation = nil; persist() }
        }
    }
    func recommend() {
        let input = request
        let preserved = selected
        launch { [self] token in
            progress = "Mencocokkan minat dan jam kunjungan…"
            let result = try await pipeline.recommend(input, now: now)
            guard epoch.isCurrent(token), !Task.isCancelled else { return }
            review = result
            selected = preserved.isEmpty ? Set(input.requiredCandidateIDs + result.suggestions.filter(\.recommended).map(\.id))
                : preserved.union(input.requiredCandidateIDs)
            prepared = nil; phase = .places
        }
    }
    func select(_ item: PlaceSuggestion) {
        guard !saving, item.selectable, !item.required else { return }
        cancel(); prepared = nil
        if selected.contains(item.id) { selected.remove(item.id) }
        else if selected.count < 6 { selected.insert(item.id) }
        else { error = "Pilih maksimal 6 tempat." }
        persist()
    }
    func toggleRequired(_ item: PlaceSuggestion) {
        guard !saving, item.selectable, var current = review else { return }
        cancel()
        if request.requiredCandidateIDs.contains(item.id) { request.requiredCandidateIDs.removeAll { $0 == item.id } }
        else {
            guard request.requiredCandidateIDs.count < 6 else { error = "Maksimal 6 tempat wajib."; return }
            request.requiredCandidateIDs.append(item.id); selected.insert(item.id)
        }
        request.revision += 1
        current.request = request
        for index in current.suggestions.indices {
            current.suggestions[index].required = request.requiredCandidateIDs.contains(current.suggestions[index].id)
        }
        review = current; prepared = nil; persist()
    }
    func verify() {
        guard let review, !selected.isEmpty else { return }
        let ids = review.suggestions.filter { selected.contains($0.id) }.map(\.id)
        launch { [self] token in
            progress = "Memeriksa lokasi pilihan…"
            let value = try await pipeline.prepare(review, selectedIDs: ids, now: now) { message in
                if epoch.isCurrent(token) { progress = message }
            }
            guard epoch.isCurrent(token), !Task.isCancelled else { return }
            prepared = value; phase = .review
        }
    }
    func choose(_ pinID: String, locationID: String) {
        cancel()
        do { try prepared?.choose(pinID, for: locationID); error = nil; persist() }
        catch { self.error = error.localizedDescription }
    }
    func generate() {
        guard let review, let prepared else { return }
        let base = session.accepted?.id
        launch { [self] token in
            progress = "Mengambil cuaca dan menyusun perjalanan…"
            let value = try await pipeline.plan(prepared, review: review, baseAcceptedID: base, now: now) { message in
                if epoch.isCurrent(token) { progress = message }
            }
            guard epoch.isCurrent(token), !Task.isCancelled else { return }
            var next = session; next.proposal = value
            saving = true; defer { saving = false }
            try await store.save(next)
            guard epoch.isCurrent(token), !Task.isCancelled else { return }
            session = next; phase = .result
        }
    }
    func accept() {
        guard canApply else { error = "Input berubah atau jadwal belum layak. Hitung ulang usulanmu."; return }
        launch { [self] token in
            saving = true; defer { saving = false }
            var next = session; try next.apply(now: now)
            try await store.save(next)
            guard epoch.isCurrent(token) else { return }
            session = next; phase = .result
        }
    }
    func reject() {
        launch { [self] token in
            saving = true; defer { saving = false }
            var next = session; next.proposal = nil
            try await store.save(next)
            guard epoch.isCurrent(token) else { return }
            session = next; phase = .home
        }
    }
    func openSaved() {
        guard let accepted = session.accepted else { return }
        do { try configureCatalog(city: accepted.request.useCityCatalog == true) }
        catch { self.error = error.localizedDescription; return }
        cancel(); request = accepted.request; prepared = accepted.prepared; selected = Set(accepted.prepared.selectedIDs)
        session.proposal = nil; phase = .result; persist()
    }
    func extend(_ stop: PlannedStop, in plan: IntegratedPlan) {
        guard stop.duration <= 330 else { return }
        do { try configureCatalog(city: plan.request.useCityCatalog == true) }
        catch { self.error = error.localizedDescription; return }
        edit { input in
            input = plan.request; input.id = UUID()
            input.durationByVenue[stop.venueID] = stop.duration + 30
            input.requiredCandidateIDs = plan.prepared.selectedIDs
        }
        phase = .preferences; recommend()
    }
    func export(_ value: IntegratedPlan) {
        launch { [self] token in
            let folder = try await store.export(value)
            guard epoch.isCurrent(token) else { return }
            exportURLs = [folder.appendingPathComponent("REPORT.md"), folder.appendingPathComponent("experiment.json")]
        }
    }
    func diagnoseWeather() {
        guard mode == .live else { return }
        launch { [self] token in
            progress = "Memeriksa WeatherKit…"
            let pin = PlacePin(id: "weather-check", name: "Bundaran HI", address: "Jakarta", latitude: -6.195, longitude: 106.823)
            let location = LocationReview(id: "weather-check", query: "Bundaran HI", candidates: [pin], selected: pin)
            var input = TripRequest(); input.allowOpenMeteo = false
            let value = try await TripWeatherCoordinator().fetch([location], request: input, now: .now, bypassCache: true)
            guard epoch.isCurrent(token) else { return }
            diagnosis = value
        }
    }
}
