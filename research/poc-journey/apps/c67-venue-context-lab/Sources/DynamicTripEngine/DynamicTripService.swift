import Foundation
import DynamicTripContracts
import PlaceContextEngine
import PlannerEngine
import ContextPilotAdapters
import VenueDiscovery

@MainActor public final class DynamicTripService {
    private struct Prepared {
        var snapshot: PlaceSnapshot
        var pins: [PlacePin]
    }
    private let directory: VenueDirectory
    private let apple: LabAppleREST
    private var prepared: [UUID: Prepared] = [:]
    private var searchedIDs: Set<String> = []
    private var busy = false

    public init(directory: VenueDirectory, apple: LabAppleREST) {
        self.directory = directory; self.apple = apple
    }

    private func begin() throws {
        guard !busy else { throw ContextError.invalid("An operation is already running. Wait for completion.") }
        busy = true
        prepared = prepared.filter { $0.value.snapshot.expiresAt > Date() }
    }

    public func search(_ input: DynamicSearchInput) async throws -> [VenuePlace] {
        try begin(); defer { busy = false }
        let places = try await directory.search(input.query, limit: 5)
        if searchedIDs.count > 100 { searchedIDs.removeAll() }
        searchedIDs.formUnion(places.compactMap(\.id))
        return places
    }

    public func prepare(_ input: DynamicPrepareInput) async throws -> DynamicPreparedPlace {
        try begin(); defer { busy = false }
        guard searchedIDs.contains(input.placeID), ContextClock.day(input.day) != nil else {
            throw ContextError.invalid("Select a result from place search and a valid Jakarta day first")
        }
        guard prepared.count < 30 else { throw ContextError.invalid("Prepared-place capacity reached. Start a fresh session.") }
        let snapshot = try directory.snapshot(id: input.placeID, day: input.day, scheduleEnrichment: input.forOrigin != true)
        guard let name = snapshot.place.displayName?.text, let point = snapshot.place.location,
              (-6.6 ... -5.9).contains(point.latitude), (106.5 ... 107.2).contains(point.longitude) else {
            throw ContextError.invalid("Place must have a verified name and location in the Jakarta pilot area")
        }
        let override = input.appleQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard override.map({ !$0.isEmpty && $0.count <= 240 }) ?? true else {
            throw ContextError.invalid("Query Apple tidak valid.")
        }
        let pins = try await directory.appleCandidates(id: input.placeID, name: name, override: override)
        let reference = PlacePin(id: "reference", name: name, address: "", latitude: point.latitude, longitude: point.longitude)
        let candidates = pins.map { pin in
            let separation = WeatherPolicy.distance(pin, reference)
            return DynamicAppleCandidate(id: pin.id, name: pin.name, address: pin.address,
                                         latitude: pin.latitude, longitude: pin.longitude, distanceFromReferenceMeters: separation,
                                         nameSupported: Self.confirmableName(snapshot: snapshot, pin: pin, separation: separation))
        }.sorted { $0.distanceFromReferenceMeters < $1.distanceFromReferenceMeters }
        let id = UUID()
        prepared[id] = .init(snapshot: snapshot, pins: pins)
        return .init(id: id, placeID: input.placeID, name: name,
                     address: snapshot.place.formattedAddress ?? "Address unavailable", evidenceURL: snapshot.place.evidenceURI,
                     attribution: snapshot.attribution, expiresAt: snapshot.expiresAt,
                     hours: VenueHoursResolver.resolve(snapshot, day: input.day, allowRegular: true, now: Date()), appleCandidates: candidates)
    }

    private func selected(_ endpoint: DynamicEndpoint, now: Date) throws -> (PlaceSnapshot, PlacePin) {
        guard let value = prepared[endpoint.preparedID], value.snapshot.expiresAt > now,
              let pin = value.pins.first(where: { $0.id == endpoint.appleCandidateID }) else {
            throw ContextError.invalid("Place selection expired or Apple candidate was not confirmed. Search again.")
        }
        guard let point = value.snapshot.place.location else { throw ContextError.invalid("Lokasi referensi hilang") }
        let reference = PlacePin(id: "reference", name: "", address: "", latitude: point.latitude, longitude: point.longitude)
        let separation = WeatherPolicy.distance(pin, reference)
        guard DynamicAppleCandidate.canConfirm(separation: separation) else {
            throw ContextError.invalid("Padanan Apple lebih dari 500 m dari tempat yang dipilih. Cari identitas lain. Batas pilot ini bukan verifikasi pintu masuk.")
        }
        guard Self.confirmableName(snapshot: value.snapshot, pin: pin, separation: separation) else {
            throw ContextError.invalid("Nama tempat dari katalog dan Apple tidak cocok meskipun dekat; cari identitas lain, jangan memakai usaha tetangga")
        }
        return (value.snapshot, pin)
    }

    private static func confirmableName(snapshot: PlaceSnapshot, pin: PlacePin, separation: Double) -> Bool {
        if snapshot.place.id?.hasPrefix("apple:") == true {
            return separation <= 25 && snapshot.place.displayName?.text == pin.name
        }
        return DynamicAppleCandidate.compatibleNames(reference: snapshot.place.displayName?.text ?? "",
                                                     apple: pin.name, address: snapshot.place.formattedAddress ?? "")
    }

    public func registerRecommendedIDs(_ ids: [String]) {
        searchedIDs.formUnion(ids.filter{VenuePlace.validID($0)})
    }
    public func selectedPlaceIDs(_ input: DynamicPlanInput) throws -> [String] {
        try input.stops.map { stop in
            guard let id = try selected(stop.endpoint, now: Date()).0.place.id else { throw ContextError.invalid("Identitas tujuan hilang") }
            return id
        }
    }
    public func plan(_ input: DynamicPlanInput, requiredIDs: Set<String>? = nil) async throws -> DynamicPlanResponse {
        try await buildPlan(input, requiredIDs: requiredIDs).baseline
    }

    public func planWithMoments(_ input: DynamicPlanInput, requiredIDs: Set<String>) async throws -> DynamicPlanChoices {
        try await buildPlan(input, requiredIDs: requiredIDs)
    }

    private func buildPlan(_ input: DynamicPlanInput, requiredIDs: Set<String>?) async throws -> DynamicPlanChoices {
        try begin(); defer { busy = false }
        let clock = ContinuousClock.now
        let now = Date()
        guard (1 ... 6).contains(input.stops.count), input.departure >= now, input.deadline > input.departure,
              (0 ... 240).contains(input.maximumWaitingMinutes), [1, 5, 15].contains(input.startStepMinutes),
              (1 ... 128).contains(input.maxTravelCalls),
              ContextClock.label(input.departure) == ContextClock.label(input.deadline.addingTimeInterval(-0.001)) else {
            throw ContextError.invalid("Plan requires 1–6 stops, a future single day and valid waiting/grid/budget bounds")
        }
        let origin = try selected(input.origin, now: now)
        let originID = "origin-" + input.origin.preparedID.uuidString
        var identities = [PilotIdentity(internalID: originID, placeID: origin.0.place.id, applePin: origin.1,
                                        evidence: "Client explicitly confirmed independent Apple search candidate", confirmedAt: now)]
        var stops: [ContextPlanStop] = []
        var weatherSources: [String] = []
        var weatherStates: [String] = []
        let weatherProvider = LabRESTWeather(apple: apple)
        for stop in input.stops {
            let (preparedSnapshot, pin) = try selected(stop.endpoint, now: now)
            guard let id = preparedSnapshot.place.id, id != origin.0.place.id else { throw ContextError.invalid("Origin cannot also be a visit") }
            let day = ContextClock.label(input.departure)
            let snapshot = try directory.snapshot(id: id, day: day, now: now)
            var request = VisitContextRequest(placeID: id, day: day)
            request.identityConfirmed = true
            request.availableStart = Self.minute(input.departure)
            request.availableEnd = Self.minute(input.deadline)
            request.durationMinutes = stop.durationMinutes
            request.startStepMinutes = input.startStepMinutes
            request.exposure = stop.exposure
            request.exposureEvidence = stop.exposure == .unknown ? nil : "User-declared activity exposure in Context Lab"
            request.preferredTime = stop.preferredTime; request.avoidRain = stop.avoidRain
            request.priorities = input.priorities
            try request.validate()
            identities.append(.init(internalID: id, placeID: id, applePin: pin,
                                    evidence: "Client explicitly confirmed independent Apple search candidate", confirmedAt: now))
            var weather: VisitWeatherContext?
            let checksRain = stop.avoidRain && stop.exposure == .outdoor
            if checksRain {
                do {
                    let start = ContextClock.calendar.dateInterval(of: .hour, for: input.departure)!.start
                    let evidence = try await weatherProvider.fetch(pin: pin, memberIDs: [id], start: start,
                                                                   end: input.deadline.addingTimeInterval(3600), allowFallback: false, now: now)
                    weather = AppleContextWeatherAdapter.convert(evidence)
                    weatherStates.append(evidence.status)
                    if let source = weather?.source { weatherSources.append(source) }
                } catch {
                    try Task.checkCancellation()
                    if checksRain {
                        if case LabRESTError.status(let code, _) = error, [401, 403, 429].contains(code) { throw error }
                        if error.localizedDescription.contains("budget_exhausted") { throw error }
                    }
                    weatherStates.append("unavailable")
                }
            }
            stops.append(.init(snapshot: snapshot, request: request, weather: weather))
        }
        guard Set(stops.map { $0.request.placeID }).count == stops.count else { throw ContextError.invalid("Duplicate selected places") }
        var request = ContextPlanRequest(originID: originID, returnID: originID,
                                         departure: input.departure, deadline: input.deadline, stops: stops)
        request.priorities = input.priorities; request.maximumTotalWaitingMinutes = input.maximumWaitingMinutes
        request.policy = input.policy; request.maxTravelCalls = input.maxTravelCalls
        request.allVisitSlots = true; request.beamWidth = 12
        let preparation = Self.seconds(clock)
        let adapter = try AppleContextTravelAdapter(identities: identities, provider: LabRESTETA(apple: apple))
        let routeClock = ContinuousClock.now
        let baseline: ContextItineraryResult
        if let requiredIDs {
            baseline = try await OptionalItineraryPlanner.plan(request, requiredIDs: requiredIDs, provider: adapter, now: Date())
        } else {
            baseline = try await ContextItineraryPlanner.plan(request, provider: adapter, now: Date())
        }
        let metrics = DynamicStageMetrics(preparationSeconds: preparation, routingSeconds: Self.seconds(routeClock),
                                          etaAdapterSeconds: adapter.providerWallSeconds, serverTotalSeconds: Self.seconds(clock), etaCalls: baseline.travelCalls,
                                          unavailableETA: adapter.metrics.failures, weatherStatus: weatherStates.isEmpty ? "not_requested" : weatherStates.joined(separator: ","), evidenceMode: "LIVE")
        return .init(baseline: .init(itinerary: baseline, metrics: metrics, weatherAttributions: weatherSources, moment: nil), alternative: nil)
    }

    public var counters: [String: Int] {
        ["appleHTTPCalls": apple.budget.calls, "etaCells": apple.budget.cells]
    }
    public static func minute(_ date: Date) -> Int {
        let c = ContextClock.calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }
    public static func seconds(_ began: ContinuousClock.Instant) -> Double {
        let c = began.duration(to: .now).components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
