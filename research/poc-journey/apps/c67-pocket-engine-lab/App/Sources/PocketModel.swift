import Foundation
import Observation
import SwiftData
import MapKit
import WeatherKit
import PocketEngine
import OSLog

private struct WorkspaceSnapshot: Codable {
    var profile: Profile
    var choices: [StopChoice]
    var departure: Date
    var deadline: Date
    var flexibleDeparture: Bool?
    var lastVenueID: String?
    var returnToOrigin: Bool
    var maxWaitMinutes: Int
    var avoidRain: Bool
    var targetStops: Int?
    var dinnerIsLast: Bool?
    var dinnerNotBefore: Int?
    var waitConsent: Bool?
    var catalog: Catalog
    var areaName: String?
    var usesLunaAdvice: Bool?
}

@MainActor @Observable
final class PocketModel {
    var catalog: Catalog? { didSet { cachedPool = nil; cachedAreaPool = nil } }
    var profile = Profile() { didSet { resetDiscovery(); invalidate() } }
    var choices: [StopChoice] = [] {
        didSet {
            if let lastVenueID, !choices.contains(where: { $0.venueID == lastVenueID }) { self.lastVenueID = nil }
            else { invalidate() }
        }
    }
    var departure: Date { didSet { invalidate() } }
    var deadline: Date { didSet { invalidate() } }
    var flexibleDeparture = false { didSet { invalidate() } }
    var lastVenueID: String? { didSet { invalidate() } }
    var returnToOrigin = true { didSet { invalidate() } }
    var maxWaitMinutes = 0 { didSet { invalidate() } }
    var waitConsent = false { didSet { invalidate() } }
    var targetStops = 3 { didSet { invalidate() } }
    var dinnerIsLast = false { didSet { dinnerNotBefore = nil; invalidate() } }
    var dinnerNotBefore: Int? { didSet { invalidate() } }
    var candidatePlan: Itinerary?
    var waitingPlan: Itinerary?
    var area: VisitArea? { didSet { cachedAreaPool = nil; resetDiscovery(); invalidate() } }
    var usesLunaAdvice = true { didSet { invalidate() } }
    var adviceNotice = ""
    var areaLabel: String { (area?.name ?? "Pilih wilayah") + (extendedArea ? " · perluasan 5 km" : "") }
    func selectArea(_ name: String) {
        do { extendedArea = false; area = try VisitArea.bundled(named: name); clearSearch() }
        catch { message = error.localizedDescription }
    }
    var extendedArea = false { didSet { resetDiscovery() } }
    var discoveryVenues: [Venue] = [] { didSet { cachedPool = nil; cachedAreaPool = nil } }
    var isDiscovering = false
    var discoveryNotice = ""
    var discoveryRequests = 0
    var discoverySeconds = 0.0
    var discoveryRan = false
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryID = UUID()
    private let logger = Logger(subsystem: "giovanchristoffel.c67-pocket-engine", category: "engine")
    var avoidRain = false { didSet { invalidate() } }
    var origin: Coordinate? { didSet { invalidate() } }
    var originName = "Pilih titik awal"
    var query = ""
    var localMatches: Set<String>?
    var appleHits: [PlaceHit] = []
    var providerHits: [ProviderHit] = []
    var providerNotice = ""
    var searchNotice = ""
    var shownCount = 12
    var isSearching = false
    var isSyncing = false
    var isLocating = false
    var isPlanning = false
    var isDrawing = false
    var message: String?
    var syncLabel = "Katalog identitas bawaan; fakta operasional belum diverifikasi."
    var plan: Itinerary?
    var routes: [MKPolyline] = []
    var routeNotice = ""
    var weatherAttribution: WeatherAttribution?
    var aiReasons: [String: [String]] = [:]
    var serverURL = UserDefaults.standard.string(forKey: "pocket.catalogURL") ?? "http://localhost:8792"
    @ObservationIgnored let apple = AppleServices()
    @ObservationIgnored let spotlight = CatalogSearch()
    @ObservationIgnored private let client = CatalogClient()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var planningTask: Task<Void, Never>?
    @ObservationIgnored private var drawingTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var activePlanID = UUID()
    @ObservationIgnored private var activeSearchID = UUID()

    init() {
        let cal = TripClock.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        departure = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        deadline = cal.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)!
    }
    @ObservationIgnored private var cachedPool: [Venue]?
    @ObservationIgnored private var cachedAreaPool: [Venue]?
    var allVenues: [Venue] {
        let independent = catalog?.venues ?? [], session = discoveryVenues
        if let cachedPool { return cachedPool }
        let pool = CandidatePool.merge(independent: independent, session: session)
        cachedPool = pool
        return pool
    }
    private var areaVenues: [Venue] {
        let pool = allVenues, area = self.area, extensionMeters = extendedArea ? 5000.0 : 0
        if let cachedAreaPool { return cachedAreaPool }
        let permitted = pool.filter { area?.permits($0.coordinate, extensionMeters: extensionMeters) ?? false }
        cachedAreaPool = permitted
        return permitted
    }
    var assessments: [Assessment] {
        areaVenues.filter { localMatches?.contains($0.id) ?? true }
            .map { Recommender.assess($0, profile: profile) }
            .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }
    var recommendations: [Assessment] { Recommender.recommendations(from: assessments, profile: profile) }
    var eligibleCount: Int { Recommender.eligibleMatches(from: assessments, profile: profile).count }
    var missingInterests: [String] {
        profile.interests.filter { interest in
            !recommendations.contains { $0.matchedInterests.contains(interest) }
        }.sorted()
    }
    private func resetDiscovery() {
        discoveryTask?.cancel(); discoveryID = UUID(); isDiscovering = false
        discoveryVenues = discoveryVenues.filter { venue in choices.contains { $0.venueID == venue.id } }; discoveryNotice = ""; discoveryRan = false
    }
    func discover(queries: [String: String] = [:]) {
        guard let area, !isDiscovering else { return }
        clearSearch(); discoveryRan = true; discoveryNotice = ""; discoveryVenues = discoveryVenues.filter { venue in choices.contains { $0.venueID == venue.id } }
        let id = UUID(); discoveryID = id; isDiscovering = true; discoveryRequests = 0
        let categories = profile.interests.isEmpty ? ["restaurant", "garden", "museum"] : profile.interests.sorted()
        let extensionMeters = extendedArea ? 5000.0 : 0
        let started = Date()
        discoveryTask = Task {
            defer {
                if discoveryID == id {
                    isDiscovering = false; discoverySeconds = Date().timeIntervalSince(started)
                    logger.info("discovery_complete requests=\(self.discoveryRequests) eligible=\(self.eligibleCount) seconds=\(self.discoverySeconds)")
                }
            }
            var failed = 0
            for category in categories.prefix(7) {
                guard discoveryID == id, !Task.isCancelled else { return }
                guard Date().timeIntervalSince(started) < 35 else {
                    discoveryNotice = "Batas waktu pencarian tercapai. Sebagian minat belum diperiksa."; break
                }
                do {
                    discoveryRequests += 1
                    let hits = try await apple.search(queries[category] ?? profile.query(for: category), area: area, extensionMeters: extensionMeters)
                    guard discoveryID == id, !Task.isCancelled else { return }
                    discoveryVenues = CandidatePool.merge(independent: discoveryVenues, session: hits.map(apple.candidate))
                } catch {
                    if Task.isCancelled { return }
                    failed += 1
                    logger.error("discovery_request_failed code=\((error as NSError).code)")
                }
            }
            if categories.count > 7 {
                discoveryNotice += " Apple Maps memeriksa tujuh minat per pencarian. Katalog lokal tetap dinilai untuk seluruh minat."
            }
            if failed > 0 { discoveryNotice += " \(failed) permintaan pencarian gagal. Coba lagi untuk melengkapinya." }
        }
    }
    func attach(_ context: ModelContext) {
        guard !attached else { return }; attached = true; self.context = context; restoring = true
        do {
            area = try VisitArea.jakartaSelatan()
            let bundled = try Catalog.bundled().validated()
            if let saved = try context.fetch(FetchDescriptor<SavedWorkspace>()).first {
                let snapshot = try Codec.decoder().decode(WorkspaceSnapshot.self, from: saved.payload)
                catalog = try snapshot.catalog.validated(); profile = snapshot.profile
                area = try VisitArea.bundled(named: snapshot.areaName ?? "Jakarta Selatan")
                usesLunaAdvice = snapshot.usesLunaAdvice ?? true
                choices = snapshot.choices.filter { choice in catalog!.venues.contains { $0.id == choice.venueID } }
                departure = snapshot.departure; deadline = snapshot.deadline; returnToOrigin = snapshot.returnToOrigin
                flexibleDeparture = snapshot.flexibleDeparture ?? false
                lastVenueID = snapshot.lastVenueID.flatMap { id in choices.contains { $0.venueID == id } ? id : nil }
                maxWaitMinutes = snapshot.maxWaitMinutes; avoidRain = snapshot.avoidRain
                targetStops = snapshot.targetStops ?? 3
                waitConsent = snapshot.waitConsent ?? false
                dinnerIsLast = snapshot.dinnerIsLast ?? false
                dinnerNotBefore = snapshot.dinnerNotBefore
                syncLabel = "Katalog tersimpan. Kesegaran bukti diperiksa lagi saat dipakai."
            } else { catalog = bundled }
        } catch { message = "Pemulihan data gagal: " + error.localizedDescription }
        restoring = false
        if let catalog { Task { do { try await spotlight.index(catalog.venues) } catch { searchNotice = "Indeks Spotlight belum tersedia; pencarian kata tetap dapat digunakan." } } }
    }
    func save() {
        guard !restoring, let context, let catalog else { return }
        do {
            let snapshot = WorkspaceSnapshot(profile: profile, choices: choices.filter { choice in catalog.venues.contains { $0.id == choice.venueID } }, departure: departure, deadline: deadline,
                                             flexibleDeparture: flexibleDeparture, lastVenueID: lastVenueID,
                                             returnToOrigin: returnToOrigin, maxWaitMinutes: maxWaitMinutes, avoidRain: avoidRain,
                                             targetStops: targetStops, dinnerIsLast: dinnerIsLast, dinnerNotBefore: dinnerNotBefore,
                                             waitConsent: waitConsent, catalog: catalog, areaName: area?.name, usesLunaAdvice: usesLunaAdvice)
            let payload = try Codec.encoder().encode(snapshot)
            if let row = try context.fetch(FetchDescriptor<SavedWorkspace>()).first { row.payload = payload }
            else { context.insert(SavedWorkspace(payload: payload)) }
            try context.save()
        } catch { message = "Perubahan belum tersimpan: " + error.localizedDescription }
    }
    private func invalidate() {
        guard !restoring else { return }
        activePlanID = UUID(); planningTask?.cancel(); drawingTask?.cancel()
        isPlanning = false; isDrawing = false; plan = nil; candidatePlan = nil; waitingPlan = nil; routes = []; routeNotice = ""; aiReasons = [:]; adviceNotice = ""
        save()
    }
    func venue(_ id: String) -> Venue? { allVenues.first { $0.id == id } }
    func add(_ venue: Venue) {
        guard !choices.contains(where: { $0.venueID == venue.id }) else { return }
        guard choices.count < 6 else { message = "Maksimal enam tujuan per rencana."; return }
        let assessment = Recommender.assess(venue, profile: profile)
        guard assessment.eligible else { message = assessment.blockers.joined(separator: "\n"); return }
        choices.append(.init(venueID: venue.id, required: false))
    }
    func update(_ choice: StopChoice) { if let i = choices.firstIndex(where: { $0.venueID == choice.venueID }) { choices[i] = choice } }
    func remove(_ id: String) { choices.removeAll { $0.venueID == id } }
    func setOrigin(name: String, point: Coordinate) { originName = name; origin = point }
    func locate() {
        guard !isLocating else { return }; isLocating = true
        Task { defer { isLocating = false }; do { setOrigin(name: "Lokasi saya", point: try await apple.currentLocation()) } catch { message = error.localizedDescription } }
    }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    func match(name: String, coordinate: Coordinate) -> Venue? {
        let name = Self.normalized(name)
        let candidates = allVenues.filter { venue in
            !venue.id.hasPrefix("apple-session-") &&
                ([venue.name] + venue.aliases).contains { Self.normalized($0) == name } && venue.coordinate.distance(to: coordinate) <= 125
        }
        return candidates.count == 1 ? candidates.first : nil
    }
    func clearSearch() {
        activeSearchID = UUID(); searchTask?.cancel(); isSearching = false
        localMatches = nil; appleHits = []; providerHits = []; searchNotice = ""; shownCount = 12
    }
    func search(_ source: SearchSource) {
        clearSearch()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = UUID(); activeSearchID = id; isSearching = true
        searchTask = Task {
            defer { if activeSearchID == id { isSearching = false } }
            do {
                switch source {
                case .catalog:
                    let words = Self.normalized(text).split(separator: " ")
                    let lexical = (catalog?.venues ?? []).filter { venue in
                        let haystack = Self.normalized(([venue.name, venue.address, venue.branch] + venue.categories + venue.aliases).joined(separator: " "))
                        return words.allSatisfy { haystack.contains($0) }
                    }.map(\.id)
                    var semantic: [String] = []
                    do { semantic = try await spotlight.find(text) }
                    catch { if !Task.isCancelled { searchNotice = "Spotlight belum tersedia; hasil memakai pencocokan kata." } }
                    guard activeSearchID == id, !Task.isCancelled else { return }
                    localMatches = Set(lexical + semantic)
                case .apple:
                    let results = try await apple.search(text)
                    guard activeSearchID == id, !Task.isCancelled else { return }; appleHits = results
                case .tomtom:
                    let results = try await client.tomtom(base: serverURL, token: TokenVault.read(), query: text,
                                                          coordinate: origin ?? Coordinate(latitude: -6.24, longitude: 106.82))
                    guard activeSearchID == id, !Task.isCancelled else { return }
                    providerHits = results.results; providerNotice = results.notice
                }
            } catch { if activeSearchID == id && !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    func sync() {
        guard !isSyncing else { return }; isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                let updated = try await client.catalog(base: serverURL, token: TokenVault.read())
                catalog = updated
                choices.removeAll { choice in !updated.venues.contains { $0.id == choice.venueID } }
                invalidate(); clearSearch()
                syncLabel = "Katalog diperbarui: \(updated.venues.count) tempat · " + updated.generatedAt.formatted(date: .abbreviated, time: .shortened)
                do { try await spotlight.index(updated.venues) } catch { searchNotice = "Katalog tersimpan, tetapi indeks Spotlight belum berhasil diperbarui." }
            } catch { message = error.localizedDescription }
        }
    }
    func acceptCandidatePlan() { plan = candidatePlan; candidatePlan = nil }
    func acceptWaitingPlan() {
        guard let waitingPlan else { return }
        let minutes = waitingPlan.stops.map { Int(ceil($0.visitStart.timeIntervalSince($0.arrival) / 60)) }.max() ?? 0
        maxWaitMinutes = minutes; waitConsent = true
        candidatePlan = waitingPlan; self.waitingPlan = nil
    }
    func computePlan(suggestWait: Bool = false) {
        guard !isPlanning else { return }
        let started = ContinuousClock.now
        guard let origin, catalog != nil else { message = "Pilih titik awal dan katalog terlebih dahulu."; return }
        let now = Date()
        let earliest = flexibleDeparture ? max(departure, now) : departure
        guard TripClock.day(departure) == TripClock.day(deadline), earliest < deadline,
              earliest >= now.addingTimeInterval(-60) else {
            message = "Pilih jendela perjalanan satu hari yang masih tersedia."
            return
        }
        if dinnerIsLast && (lastVenueID == nil || dinnerNotBefore == nil) {
            message = "Pilih tujuan terakhir dan konfirmasikan batas awal makan malam terlebih dahulu."; return
        }
        var selectedChoices = choices
        if dinnerIsLast, let lastVenueID, let dinnerNotBefore, let index = selectedChoices.firstIndex(where: { $0.venueID == lastVenueID }) {
            if case .required(let minute) = selectedChoices[index].timing, minute < dinnerNotBefore {
                message = "Jam wajib tujuan terakhir lebih awal dari batas makan malam. Pilih jam yang sesuai."; return
            }
            if case .required = selectedChoices[index].timing {} else { selectedChoices[index].timing = .notBefore(dinnerNotBefore) }
        }
        let input = TripInput(departure: earliest, deadline: deadline, origin: origin,
                              returnToOrigin: returnToOrigin, maxWaitMinutes: suggestWait ? 30 : (waitConsent ? maxWaitMinutes : 0), avoidRain: avoidRain,
                              latestDeparture: flexibleDeparture ? deadline : nil, lastVenueID: lastVenueID, maximumStops: min(targetStops, choices.count))
        let choices = selectedChoices, profile = profile, venues = allVenues, id = UUID()
        let useLuna = usesLunaAdvice, base = serverURL, token = TokenVault.read()
        activePlanID = id; plan = nil; candidatePlan = nil; waitingPlan = nil; routes = []; isPlanning = true
        apple.resetWeather()
        let logger = self.logger
        planningTask = Task {
            defer { if activePlanID == id { isPlanning = false } }
            do {
                let options = try await ItineraryPlanner.makeOptions(input: input, choices: choices, venues: venues, profile: profile,
                                                                     travel: { [apple] from, to, date in try await apple.eta(from: from, to: to, at: date) },
                                                                     weather: { [apple] point, start, end in try await apple.weather(at: point, from: start, through: end) },
                                                                     report: { event in Self.logPlanning(event, with: logger) })
                guard activePlanID == id, !Task.isCancelled else { return }
                let result: Itinerary
                if useLuna {
                    adviceNotice = "Luna Max sedang membandingkan \(options.count) pilihan jadwal…"
                    let menu = VisitAdviceRequest(plans: options, venues: venues, profile: profile, choices: choices)
                    let answer = try await client.visitAdvice(base: base, token: token, request: menu)
                    guard activePlanID == id, !Task.isCancelled else { return }
                    result = try menu.selected(answer.slotID, from: options)
                    adviceNotice = "Luna Max memilih \(answer.slotID) · \(Int(answer.elapsedMS)) ms. Jadwal diperiksa ulang oleh planner."
                    logger.info("luna_selected slot=\(answer.slotID, privacy: .public) requested=\(answer.requestedModel, privacy: .public) reported=\(answer.reportedModel, privacy: .public) elapsed_ms=\(answer.elapsedMS)")
                } else {
                    result = options[0]
                    adviceNotice = "Saran Luna dinonaktifkan pengguna; jadwal dipilih planner Swift."
                }
                try ItineraryPlanner.validateSelection(result, input: input, choices: choices, venues: venues, profile: profile)
                guard activePlanID == id, !Task.isCancelled else { return }
                weatherAttribution = apple.attribution
                logger.info("plan_complete stops=\(result.stops.count) eta_requests=\(result.etaRequests) truncated=\(result.searchTruncated)")
                if suggestWait { waitingPlan = result }
                else if result.stops.count < targetStops { candidatePlan = result }
                else { plan = result }
                logger.info("plan_published elapsed_ms=\(Self.milliseconds(started.duration(to: .now)))")
            } catch { if activePlanID == id && !Task.isCancelled { adviceNotice = "Penyusunan gagal; jadwal belum diterbitkan. Ulangi setelah memeriksa koneksi dan konfigurasi."; message = error.localizedDescription; logger.error("plan_failed code=\((error as NSError).code)") } }
        }
    }
    nonisolated private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
    nonisolated private static func logPlanning(_ event: PlanningEvent, with logger: Logger) {
        switch event {
        case .firstSchedule(let duration):
            logger.info("planner_first_schedule elapsed_ms=\(milliseconds(duration))")
        case .etaAttempt(let number, let elapsed, let success):
            logger.info("planner_eta attempt=\(number) elapsed_ms=\(milliseconds(elapsed)) success=\(success)")
        case .etaCacheHit:
            logger.info("planner_eta_cache_hit")
        case .etaRetry:
            logger.info("planner_eta_retry")
        case .finished(let duration):
            logger.info("planner_finished elapsed_ms=\(milliseconds(duration))")
        }
    }
    func cancelPlanning() { invalidate() }
    func drawRoutes() {
        guard let plan, !isDrawing else { return }; isDrawing = true; routes = []; routeNotice = ""
        let id = activePlanID
        let started = ContinuousClock.now
        drawingTask = Task {
            defer {
                if activePlanID == id {
                    isDrawing = false
                    logger.info("route_geometry elapsed_ms=\(Self.milliseconds(started.duration(to: .now))) routes=\(self.routes.count)")
                }
            }
            var point = plan.origin
            let legs = plan.stops.map { ($0.coordinate, $0.departure) } + (plan.returnToOrigin ? [(plan.origin, plan.stops.last!.visitEnd)] : [])
            for (end, date) in legs {
                guard activePlanID == id, !Task.isCancelled else { return }
                do { let route = try await apple.route(from: point, to: end, at: date); if activePlanID == id { routes.append(route.polyline) } }
                catch { if !Task.isCancelled { routeNotice = "Sebagian geometri belum tersedia. Jadwal tetap memakai hasil ETA sebelumnya." } }
                point = end
            }
        }
    }
    func explain(_ venue: Venue) async {
        let id = activePlanID
        do {
            let reasons = try await AppleExplanation.select(from: Recommender.assess(venue, profile: profile))
            if activePlanID == id { aiReasons[venue.id] = reasons }
        }
        catch { if activePlanID == id { message = error.localizedDescription } }
    }
    func saveConnection(token: String) {
        do { _ = try CatalogClient.validate(serverURL); try TokenVault.write(token); UserDefaults.standard.set(serverURL, forKey: "pocket.catalogURL"); message = "Alamat dan token tersimpan. Koneksi belum diperiksa." }
        catch { message = error.localizedDescription }
    }
}

enum SearchSource: String, CaseIterable, Identifiable {
    case catalog, apple, tomtom
    var id: String { rawValue }
    var title: String { switch self { case .catalog: "Katalog"; case .apple: "Apple Maps"; case .tomtom: "TomTom" } }
}
