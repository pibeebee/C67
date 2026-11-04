import Foundation
import Observation
import TripSenseCore

@MainActor @Observable final class TripViewModel {
    var city = "Central Jakarta"
    var customOrigin = false
    var origin = Coordinate(-6.1754, 106.8272)
    var theme: Theme = .history
    var date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    }()
    var hours = 5.0
    var mode: TravelMode = .walking
    var count = 3
    var visitMinutes = 45.0
    var bufferMinutes = 5.0
    var request = "Historical and cultural attractions in Central Jakarta"
    var timeZoneID = "Asia/Jakarta"
    var requireHours = false
    var demo = false
    var busy = false
    var error: String?
    var itinerary: Itinerary?
    var diagnostics = Diagnostics()
    var candidatePlaces: [Place] = []
    var lockedIDs: Set<String> = []
    private var task: Task<Void, Never>?
    private var generationID = UUID()
    private var maps: MapServices?
    private var opening: (any OpeningHoursProviding)?
    private var recommendations: [Recommendation] = []
    private var generatedPreferences: TripPreferences?
    private var generatedDemo = false
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var available: Bool { ModelPlanner.isAvailable }
    var resultTimeZone = TimeZone(identifier: "Asia/Jakarta")!
    var availability: String { ModelPlanner.availability }
    var languages: String { ModelPlanner.languageStatus }
    var resultOrigin: Coordinate? { generatedPreferences?.origin }
    var isDemoResult: Bool { generatedDemo }

    func cancel() { task?.cancel(); task = nil; generationID = UUID(); busy = false }

    func generate() {
        cancel()
        diagnostics = Diagnostics(); error = nil; itinerary = nil; candidatePlaces = []; lockedIDs = []; busy = true
        guard let zone = TimeZone(identifier: timeZoneID) else { error = "Enter a valid time zone ID."; busy = false; return }
        let id = generationID, demoMode = demo, useCustom = customOrigin, cityQuery = city
        let userRequest = useCustom ? "Destination: \(cityQuery). Preferences: \(request.replacingOccurrences(of: "Central Jakarta", with: cityQuery))" : request
        var preferences = TripPreferences(origin: origin, start: date, duration: hours * 3600,
                                          theme: theme, mode: mode, count: count,
                                          visitDuration: visitMinutes * 60, buffer: bufferMinutes * 60,
                                          timeZoneID: zone.identifier, requireHours: requireHours)
        let log = diagnostics
        log.phase = "Searching and selecting places…"
        let service = MapServices(diagnostics: log)
        let provider: any OpeningHoursProviding = demoMode ? FixtureHoursProvider(start: preferences.start) : OSMHoursProvider(diagnostics: log)
        maps = service; opening = provider
        task = Task {
            defer { if id == generationID { busy = false; task = nil } }
            do {
                if !demoMode { try ModelPlanner.requireAvailability(available) }
                if useCustom && !demoMode { preferences.origin = try await service.resolveOrigin(cityQuery) }
                try Task.checkCancellation()
                let proposed: [Recommendation]
                let all: [Place]
                let routes: any RouteProviding
                if demoMode {
                    log.record("DEMO ONLY: no Foundation Model, live search or live route was invoked.")
                    proposed = DemoFixture.recommendations(theme: preferences.theme, count: preferences.count)
                    all = DemoFixture.places; routes = FixtureRoutes()
                } else {
                    proposed = try await ModelPlanner.select(preferences: preferences, request: userRequest, maps: service, diagnostics: log)
                    all = service.places; routes = service
                }
                let eligible = all.filter { preferences.theme == .mixed || $0.themes.contains(preferences.theme) }
                guard eligible.count >= preferences.count else { throw PlanningError.noPlaces }
                let poolChoices = try CandidateSelector.select(places: eligible,
                                                               proposed: proposed.filter { candidate in eligible.contains { $0.id == candidate.placeID } },
                                                               theme: preferences.theme, count: min(6, eligible.count))
                let catalog = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })
                let pool = poolChoices.compactMap { catalog[$0.placeID] }
                let poolIDs = Set(pool.map(\.id))
                let selectedRecommendations = proposed.filter { poolIDs.contains($0.placeID) }
                try Task.checkCancellation()
                guard id == generationID else { return }
                resultTimeZone = zone; generatedPreferences = preferences; generatedDemo = demoMode
                candidatePlaces = pool; recommendations = selectedRecommendations
                service.beginOptimization()
                let result = try await RouteOptimizer(routes: routes, hours: provider, diagnostics: log).optimize(
                    .init(preferences: preferences, places: pool, recommendations: selectedRecommendations))
                try Task.checkCancellation()
                guard id == generationID else { return }
                itinerary = result
            } catch is CancellationError {} catch {
                guard id == generationID else { return }
                self.error = error.localizedDescription
                log.record("Planning failed; no schedule accepted. Details shown in the error message.")
            }
        }
    }

    func osmWebsite(for id: String) -> URL? { (opening as? OSMHoursProvider)?.websites[id] }
    func osmSource(for id: String) -> URL? { (opening as? OSMHoursProvider)?.sourceLinks[id] }

    func setLocked(_ id: String, locked: Bool) {
        if locked { lockedIDs.insert(id) } else { lockedIDs.remove(id) }
    }

    func reoptimize() {
        guard !busy, var preferences = generatedPreferences, let service = maps, let provider = opening else { return }
        preferences.requireHours = requireHours
        guard lockedIDs.count <= preferences.count else { error = "Locked places exceed the requested stop count."; return }
        runUpdate(preferences: preferences, pool: candidatePlaces, choices: recommendations, locked: lockedIDs, service: service, provider: provider)
    }

    func remove(_ stop: ScheduledStop) {
        guard !busy, let existing = itinerary, var preferences = generatedPreferences, let service = maps, let provider = opening else { return }
        let keep = existing.stops.filter { $0.id != stop.id }
        if keep.isEmpty { itinerary = nil; candidatePlaces = []; lockedIDs = []; return }
        preferences.count = keep.count
        let pool = keep.map(\.place)
        let choices = keep.map { Recommendation($0.id, reason: $0.reason) }
        runUpdate(preferences: preferences, pool: pool, choices: choices, locked: Set(pool.map(\.id)), service: service, provider: provider, removal: true)
    }

    private func runUpdate(preferences: TripPreferences, pool: [Place], choices: [Recommendation], locked: Set<String>,
                           service: MapServices, provider: any OpeningHoursProviding, removal: Bool = false) {
        busy = true; error = nil; let id = generationID; let log = diagnostics
        let routes: any RouteProviding = generatedDemo ? FixtureRoutes() : service
        service.beginOptimization()
        task = Task {
            defer { if id == generationID { busy = false; task = nil } }
            do {
                let result = try await RouteOptimizer(routes: routes, hours: provider, diagnostics: log).optimize(
                    .init(preferences: preferences, places: pool, recommendations: choices, lockedIDs: locked, enforceVariety: !removal))
                try Task.checkCancellation()
                guard id == generationID else { return }
                itinerary = result; generatedPreferences = preferences
                if removal { candidatePlaces = pool; recommendations = choices; lockedIDs.formIntersection(Set(pool.map(\.id))) }
            } catch is CancellationError {} catch {
                guard id == generationID else { return }
                self.error = "Recalculation failed. Previous itinerary retained. " + error.localizedDescription
            }
        }
    }
}
