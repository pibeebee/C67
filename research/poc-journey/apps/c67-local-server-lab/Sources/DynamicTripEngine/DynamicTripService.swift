import Foundation
import DynamicTripContracts
import PlaceContextEngine
import PlannerEngine
import ContextPilotAdapters

@MainActor public final class DynamicTripService {
    private struct Prepared {
        var snapshot: PlaceSnapshot
        var pins: [PlacePin]
    }
    private let google: GooglePlacesClient
    private let apple: LabAppleREST
    private var prepared: [UUID: Prepared] = [:]
    private var searchedIDs: Set<String> = []
    private var busy = false

    public init(google: GooglePlacesClient, apple: LabAppleREST) {
        self.google = google; self.apple = apple
    }

    private func begin() throws {
        guard !busy else { throw ContextError.invalid("An operation is already running. Wait for completion.") }
        busy = true
        prepared = prepared.filter { $0.value.snapshot.expiresAt > Date() }
    }

    public func search(_ input: DynamicSearchInput) async throws -> [GooglePlace] {
        try begin(); defer { busy = false }
        let places = try await google.search(input.query, limit: 5)
        if searchedIDs.count > 100 { searchedIDs.removeAll() }
        searchedIDs.formUnion(places.compactMap(\.id))
        return places
    }

    public func prepare(_ input: DynamicPrepareInput) async throws -> DynamicPreparedPlace {
        try begin(); defer { busy = false }
        guard searchedIDs.contains(input.googlePlaceID), ContextClock.day(input.day) != nil else {
            throw ContextError.invalid("Select a result from place search and a valid Jakarta day first")
        }
        guard prepared.count < 30 else { throw ContextError.invalid("Prepared-place capacity reached. Start a fresh session.") }
        let snapshot = try await google.details(input.googlePlaceID, now: Date())
        guard let name = snapshot.place.displayName?.text, let point = snapshot.place.location,
              (-6.6 ... -5.9).contains(point.latitude), (106.5 ... 107.2).contains(point.longitude) else {
            throw ContextError.invalid("Place must have a verified name and location in the Jakarta pilot area")
        }
        let query = input.appleQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (name + " Jakarta")
        guard !query.isEmpty, query.count <= 240 else { throw ContextError.invalid("Invalid Apple search query") }
        let pins = try await LabRESTSearch(apple: apple).search(query: query).filter {
            (-6.6 ... -5.9).contains($0.latitude) && (106.5 ... 107.2).contains($0.longitude)
        }
        let reference = PlacePin(id: "reference", name: name, address: "", latitude: point.latitude, longitude: point.longitude)
        let candidates = pins.map { pin in
            let separation = WeatherPolicy.distance(pin, reference)
            return DynamicAppleCandidate(id: pin.id, name: pin.name, address: pin.address,
                                         latitude: pin.latitude, longitude: pin.longitude, distanceFromGoogleMeters: separation,
                                         nameSupported: Self.confirmableName(snapshot: snapshot, pin: pin, separation: separation))
        }.sorted { $0.distanceFromGoogleMeters < $1.distanceFromGoogleMeters }
        let id = UUID()
        prepared[id] = .init(snapshot: snapshot, pins: pins)
        return .init(id: id, googlePlaceID: input.googlePlaceID, name: name,
                     address: snapshot.place.formattedAddress ?? "Address unavailable", googleMapsURL: snapshot.place.googleMapsUri,
                     attribution: snapshot.attribution, expiresAt: snapshot.expiresAt,
                     hours: GoogleHoursResolver.resolve(snapshot, day: input.day, allowRegular: true, now: Date()), appleCandidates: candidates)
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
            throw ContextError.invalid("Padanan Apple lebih dari 500 m dari tempat yang dipilih; cari identitas lain. Batas pilot ini bukan verifikasi pintu masuk.")
        }
        guard Self.confirmableName(snapshot: value.snapshot, pin: pin, separation: separation) else {
            throw ContextError.invalid("Nama khas tempat Google dan Apple tidak cocok meskipun dekat; cari identitas lain, jangan memakai usaha tetangga")
        }
        return (value.snapshot, pin)
    }

    private static func confirmableName(snapshot: PlaceSnapshot, pin: PlacePin, separation: Double) -> Bool {
        if let id = snapshot.place.id,
           let matches = SunsetVenueEvidence.beachNameMatch(placeID: id, appleName: pin.name, separationMeters: separation) {
            return matches
        }
        return DynamicAppleCandidate.compatibleNames(google: snapshot.place.displayName?.text ?? "",
                                                     apple: pin.name, address: snapshot.place.formattedAddress ?? "")
    }

    public func registerRecommendedIDs(_ ids: [String]) {
        searchedIDs.formUnion(ids.filter{GooglePlacesClient.validID($0)})
    }
    public func selectedPlaceIDs(_ input: DynamicPlanInput) throws -> [String] {
        try input.stops.map { stop in
            guard let id = try selected(stop.endpoint, now: Date()).0.place.id else { throw ContextError.invalid("Identitas tujuan hilang") }
            return id
        }
    }
    public func plan(_ input: DynamicPlanInput, requiredIDs: Set<String>? = nil) async throws -> DynamicPlanResponse {
        try await buildPlan(input, requiredIDs: requiredIDs, considerMoments: false).baseline
    }

    public func planWithMoments(_ input: DynamicPlanInput, requiredIDs: Set<String>) async throws -> DynamicPlanChoices {
        try await buildPlan(input, requiredIDs: requiredIDs, considerMoments: true)
    }

    private func buildPlan(_ input: DynamicPlanInput, requiredIDs: Set<String>?, considerMoments: Bool) async throws -> DynamicPlanChoices {
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
        var identities = [PilotIdentity(internalID: originID, googlePlaceID: origin.0.place.id, applePin: origin.1,
                                        evidence: "Client explicitly confirmed independent Apple search candidate", confirmedAt: now)]
        var stops: [ContextPlanStop] = []
        var moments: [VisitOpportunity] = []
        var weatherSources: [String] = []
        var weatherStates: [String] = []
        let weatherProvider = LabRESTWeather(apple: apple)
        for stop in input.stops {
            let (snapshot, pin) = try selected(stop.endpoint, now: now)
            guard let id = snapshot.place.id, id != origin.0.place.id else { throw ContextError.invalid("Origin cannot also be a visit") }
            var request = VisitContextRequest(placeID: id, day: ContextClock.label(input.departure))
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
            identities.append(.init(internalID: id, googlePlaceID: id, applePin: pin,
                                    evidence: "Client explicitly confirmed independent Apple search candidate", confirmedAt: now))
            var weather: VisitWeatherContext?
            let checksRain = stop.avoidRain && stop.exposure == .outdoor
            let checksSunset = considerMoments && id == SunsetVenueEvidence.placeID
                && stop.preferredTime == nil && stop.exposure == .outdoor
            if checksRain || checksSunset {
                do {
                    let start = ContextClock.calendar.dateInterval(of: .hour, for: input.departure)!.start
                    let evidence = try await weatherProvider.fetch(pin: pin, memberIDs: [id], start: start,
                                                                   end: input.deadline.addingTimeInterval(3600), allowFallback: false, now: now)
                    weather = AppleContextWeatherAdapter.convert(evidence)
                    if checksSunset, let moment = SunsetOpportunityPolicy.moment(placeID: id, day: request.day, weather: evidence, now: now) {
                        moments.append(moment)
                    }
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
        request.order = input.order ?? .optimized
        let preparation = Self.seconds(clock)
        let eta = LabRESTETA(apple: apple)
        let adapter: any MeasuredContextTravelProvider
        if input.transport == .transjakarta {
            adapter = try BuswayContextAdapter(identities: identities, provider: eta)
        } else {
            adapter = try AppleContextTravelAdapter(identities: identities, provider: eta)
        }
        let routeClock = ContinuousClock.now
        var baseline: ContextItineraryResult
        var baselineMoment: VisitOpportunity?
        var alternate: ContextItineraryResult?
        var alternateMoment: VisitOpportunity?
        if let requiredIDs, !moments.isEmpty {
            let options = try await OpportunityItineraryPlanner.plan(request, requiredIDs: requiredIDs,
                                                                     moments: moments, provider: adapter, now: Date())
            baseline = options.baseline
            baselineMoment = options.baselineMoment
            alternate = options.alternative
            alternateMoment = options.alternativeMoment
        } else if let requiredIDs {
            baseline = try await OptionalItineraryPlanner.plan(request, requiredIDs: requiredIDs, provider: adapter, now: Date())
        } else {
            baseline = try await ContextItineraryPlanner.plan(request, provider: adapter, now: Date())
        }
        if input.transport == .transjakarta {
            baseline.warnings.append("TJ uses an attributed static GTFS snapshot and estimated headways, not real-time arrivals. Access/transfer weather exposure is unknown.")
        }
        var metrics = DynamicStageMetrics(preparationSeconds: preparation, routingSeconds: Self.seconds(routeClock),
                                          etaAdapterSeconds: adapter.providerWallSeconds, serverTotalSeconds: Self.seconds(clock), etaCalls: baseline.travelCalls,
                                          unavailableETA: eta.metrics.failures, weatherStatus: weatherStates.isEmpty ? "not_requested" : weatherStates.joined(separator: ","), evidenceMode: input.transport == .transjakarta ? "LIVE_WALKING_STATIC_GTFS" : "LIVE")
        metrics.providerCalls = eta.metrics.calls; metrics.providerCells = eta.metrics.cells
        return .init(baseline: .init(itinerary: baseline, metrics: metrics, weatherAttributions: weatherSources, moment: baselineMoment),
                     alternative: alternate.map { .init(itinerary: $0, metrics: metrics, weatherAttributions: weatherSources, moment: alternateMoment) })
    }

    public var counters: [String: Int] {
        ["googleCalls": google.requests, "appleHTTPCalls": apple.budget.calls, "etaCells": apple.budget.cells]
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
