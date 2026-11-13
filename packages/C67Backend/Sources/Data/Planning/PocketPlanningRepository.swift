import Foundation
import CryptoKit
import OSLog
import C67Domain
import PocketEngine

/// Runs the tested Pocket recommender/solver locally; only catalog and constrained advice use the server.
public actor PocketPlanningRepository: PlanningRepository {
    public nonisolated let supportsOnDevicePlanning = true
    public nonisolated let preferenceLabels: [PlanningPreferenceLabel] = Interests.groups.dropFirst().flatMap { group in
        group.keys.map { PlanningPreferenceLabel(id: $0, title: Interests.title($0), group: group.title, allowsCondition: Facet(rawValue: $0)?.isCategoryLabel == false) }
    }
    private enum Receipt: Codable {
        case job(Data, UUID)
        case trip(Data, PersonalPlanningTrip)
    }
    private struct State: Codable {
        var jobs: [UUID: PlanningJob] = [:]
        var trips: [UUID: PersonalPlanningTrip] = [:]
        var receipts: [UUID: Receipt] = [:]
        var applied: [UUID: PersonalPlanningTrip] = [:]
        var pending: UUID?
    }
    private var state: State
    private var catalog: Catalog?
    private var sessionVenues: [Venue] = []
    private let services: PocketPlanningServices
    private let connection: any PocketConnectionProviding
    private let storageURL: URL?
    private let synthetic: Bool
    private var configurationRevision = 0
    private let logger = Logger(subsystem: "io.pibeebee.c67", category: "pocket-planning")

    public init(services: PocketPlanningServices, connection: any PocketConnectionProviding, storageURL: URL?, synthetic: Bool = false) throws {
        self.services = services; self.connection = connection; self.storageURL = storageURL; self.synthetic = synthetic
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: storageURL))
            for id in state.jobs.keys where state.jobs[id]?.status == .running {
                state.jobs[id]?.status = .failed; state.jobs[id]?.errorCode = "JOB_EXPIRED"
            }
        } else { state = State() }
    }

    public static func defaultStorageURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PocketPlanning", isDirectory: true).appendingPathComponent("trips-v1.json")
    }
    public func engineConnection() async -> PlanningConnection? {
        let value = await connection.credentials()
        return .init(serverURL: value.serverURL, hasToken: !value.token.isEmpty)
    }
    public func updateEngineConnection(serverURL: String, token: String) async throws {
        try await connection.update(serverURL: serverURL, token: token)
        configurationRevision += 1
        catalog = nil; sessionVenues = []
    }

    public func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob {
        try request.input.validate(purpose: request.purpose)
        let fingerprint = try Self.fingerprint(request)
        if let receipt = state.receipts[request.requestID] {
            guard case .job(let prior, let id) = receipt, prior == fingerprint, let job = state.jobs[id] else { throw PlanningError.requestConflict }
            return job
        }
        var input = request.input
        if request.purpose == .replan {
            guard let id = request.tripID, let trip = state.trips[id], trip.revision == request.baseRevision,
                  trip.input == input, trip.status != .completed else { throw PlanningError.revisionConflict }
            if trip.status == .active {
                let remaining = trip.plan.stops.filter { !trip.completedStopIDs.contains($0.id) }
                guard let first = remaining.first else { throw PlanningError.invalidInput }
                let current = trip.currentStopID == first.id
                input.startsAt = .now
                input.origin = current ? first.location : request.currentOrigin ?? trip.plan.stops.last(where: { trip.completedStopIDs.contains($0.id) })?.location ?? input.origin
                input.firstPlaceID = current ? first.id : nil
                input.places = remaining.compactMap { stop in
                    guard var place = trip.input.places.first(where: { $0.id == stop.id }) else { return nil }
                    if current && stop.id == first.id { place.visitSeconds = max(0, Int(ceil(stop.departureAt.timeIntervalSinceNow))) }
                    return place
                }
                input.preservesPlaceOrder = true
            }
        }
        var job = PlanningJob(id: UUID(), status: .running, purpose: request.purpose, input: input,
                              tripID: request.tripID, baseRevision: request.baseRevision, result: nil, errorCode: nil, createdAt: .now)
        var next = state
        next.jobs[job.id] = job; next.receipts[request.requestID] = .job(fingerprint, job.id); next.pending = job.id
        try commit(next)
        let started = ContinuousClock.now
        let revision = configurationRevision
        do {
            let result = try await execute(input, purpose: request.purpose)
            try Task.checkCancellation()
            guard revision == configurationRevision else { throw CancellationError() }
            job.status = .succeeded; job.result = result
            next = state; next.jobs[job.id] = job; try commit(next)
            logger.info("request_complete purpose=\(request.purpose.rawValue, privacy: .public) elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
            return job
        } catch {
            job.status = .failed; job.errorCode = "PROVIDER_UNAVAILABLE"
            next = state; next.jobs[job.id] = job; try commit(next)
            logger.error("request_failed purpose=\(request.purpose.rawValue, privacy: .public) code=\((error as NSError).code)")
            throw error
        }
    }

    private func execute(_ input: PlanningInput, purpose: PlanningPurpose) async throws -> PlanningResult {
        guard let options = input.enginePreferences,
              input.timeZone == "Asia/Jakarta", ["jakarta-selatan", "kemayoran"].contains(options.area),
              (0 ... 120).contains(options.maximumWaitMinutes) else { throw PlanningError.invalidInput }
        if purpose != .suggest && options.usesLuna && !options.allowsAIProcessing {
            throw EngineError.invalid("Allow sending place names and schedule options to Luna Max, or turn Luna off.")
        }
        let area = try VisitArea.bundled(named: options.area == "kemayoran" ? "Kemayoran" : "Jakarta Selatan")
        let profile = try Self.profile(options)
        var warnings: [String] = []
        do { catalog = try await services.catalog().validated() }
        catch {
            try Task.checkCancellation()
            guard catalog != nil else { throw error }
            warnings.append("Catalog sync failed; using the last independent catalog. Evidence freshness is still checked.")
        }
        guard let catalog else { throw PlanningError.unavailable }
        if purpose == .suggest {
            do { sessionVenues = try await services.discover(profile, area) }
            catch { try Task.checkCancellation(); warnings.append("Apple search unavailable; results only cover the independent catalog.") }
        }
        let pool = CandidatePool.merge(independent: catalog.venues, session: sessionVenues)
        if purpose == .suggest {
            let selected = Set(input.places.map(\.id))
            let assessments = pool.filter { area.contains($0.coordinate) && !selected.contains(Self.identity($0.id)) }
                .map { venue in
                    var assessment = Recommender.assess(venue, profile: profile)
                    if assessment.score > 0 && Self.hasAvailabilityEvidence(venue) { assessment.score += 1 }
                    return assessment
                }
            var matches = Recommender.recommendations(from: assessments, profile: profile)
            let missing = profile.interests.filter { interest in !matches.contains { $0.matchedInterests.contains(interest) } }
            if !missing.isEmpty {
                warnings.append("No sufficient matches for: " + missing.sorted().map(Interests.title).joined(separator: ", ") + ". Change your interests or area; no interest was removed automatically.")
                matches = []
            }
            if matches.isEmpty { warnings.append("Fewer than three matching places have sufficient preference evidence. Refine interests, area or conditions; no replacements were invented.") }
            warnings.append("Category matches do not establish opening hours or public access. Confirm visit availability before planning.")
            return .init(candidates: matches.prefix(12).map { Self.place($0.venue) }, warnings: warnings, synthetic: synthetic)
        }
        guard !input.places.isEmpty else { throw PlanningError.invalidInput }
        var venues: [Venue] = []
        var choices: [StopChoice] = []
        var sourceToUI: [String: UUID] = [:]
        for place in input.places {
            let point = Coordinate(latitude: place.location.latitude, longitude: place.location.longitude)
            let exact = pool.filter { $0.id == place.sourceID || Self.identity($0.id) == place.id }
            let candidates = exact.isEmpty ? pool.filter {
                $0.coordinate.distance(to: point) <= 125 && ([$0.name] + $0.aliases).map(CandidatePool.normalizedName).contains(CandidatePool.normalizedName(place.name))
            } : exact
            guard candidates.count <= 1 else { throw EngineError.invalid("A place matches multiple branches. Select its exact location again.") }
            let venue = candidates.first ?? Venue(id: "selected-" + place.id.uuidString, name: place.name, branch: place.name, address: "", coordinate: point,
                                                  categories: place.categories, license: "Traveller-selected place · current session")
            guard sourceToUI[venue.id] == nil, area.contains(venue.coordinate) else { throw EngineError.invalid("Select distinct places inside the chosen area.") }
            guard (900 ... 14400).contains(place.visitSeconds), place.visitSeconds % 60 == 0 else {
                throw EngineError.invalid("Pocket visits must last 15–240 whole minutes. Finish a shorter current visit before replanning.")
            }
            var confirmation: TripOverride?
            if let value = place.visitConfirmation {
                let day = TripClock.calendar.startOfDay(for: input.startsAt)
                let opens = Int(ceil(value.opensAt.timeIntervalSince(day) / 60)), closes = Int(floor(value.closesAt.timeIntervalSince(day) / 60))
                guard opens >= 0, closes <= 1440, closes > opens else { throw EngineError.invalid("Visit confirmation must apply to this trip date.") }
                confirmation = .init(day: TripClock.day(input.startsAt), opens: opens, closes: closes, publicAccessConfirmed: value.publicAccessConfirmed)
            }
            if let date = place.preferredAfter, TripClock.day(date) != TripClock.day(input.startsAt) { throw PlanningError.invalidInput }
            let timing = place.preferredAfter.map { date -> VisitTiming in
                let minute = TripClock.calendar.component(.hour, from: date) * 60 + TripClock.calendar.component(.minute, from: date)
                switch place.visitTiming ?? .preferred {
                case .preferred: return .preferred(minute)
                case .required: return .required(minute)
                case .notBefore: return .notBefore(minute)
                }
            }
            choices.append(.init(venueID: venue.id, required: true, durationMinutes: place.visitSeconds / 60, override: confirmation, timing: timing))
            venues.append(venue); sourceToUI[venue.id] = place.id
        }
        let last = options.lastPlaceID.flatMap { id in sourceToUI.first { $0.value == id }?.key }
        let first = input.firstPlaceID.flatMap { id in sourceToUI.first { $0.value == id }?.key }
        guard options.lastPlaceID == nil || last != nil, input.firstPlaceID == nil || first != nil else { throw PlanningError.invalidInput }
        let trip = TripInput(departure: input.startsAt, deadline: input.finishBy,
                             origin: .init(latitude: input.origin.latitude, longitude: input.origin.longitude),
                             returnToOrigin: options.returnToOrigin, maxWaitMinutes: options.maximumWaitMinutes, avoidRain: options.avoidRain,
                             latestDeparture: options.flexibleDeparture ? input.finishBy : nil, lastVenueID: last,
                             minimumStops: input.places.count, maximumStops: input.places.count,
                             preservesOrder: input.preservesPlaceOrder, firstVenueID: first)
        let services = self.services, mode = input.mode, logger = self.logger
        let plans = try await ItineraryPlanner.makeOptions(input: trip, choices: choices, venues: venues, profile: profile,
                                                           travel: { try await services.travel($0, $1, $2, mode) }, weather: services.weather,
                                                           report: { event in
                                                               switch event {
                                                               case .etaAttempt(let count, _, let success): logger.info("eta_attempt number=\(count) succeeded=\(success)")
                                                               case .firstSchedule(let duration): logger.info("first_schedule elapsed=\(String(describing: duration), privacy: .public)")
                                                               case .finished(let duration): logger.info("solver_finished elapsed=\(String(describing: duration), privacy: .public)")
                                                               default: break
                                                               }
                                                           })
        let plan: Itinerary
        if options.usesLuna {
            guard options.allowsAIProcessing else { throw EngineError.invalid("Allow sending place names and schedule options to Luna Max, or turn Luna off.") }
            let menu = VisitAdviceRequest(plans: plans, venues: venues, profile: profile, choices: choices)
            let adviceStarted = ContinuousClock.now
            let advice = try await services.advise(menu).validated()
            plan = try menu.selected(advice.slotID, from: plans)
            logger.info("luna_selected slot=\(advice.slotID, privacy: .public) elapsed=\(String(describing: adviceStarted.duration(to: .now)), privacy: .public)")
            warnings.append("Luna Max selected a validated schedule option. It did not supply place facts or route times.")
        } else { plan = plans[0]; warnings.append("Luna is disabled; the on-device planner selected the schedule.") }
        try Task.checkCancellation()
        try ItineraryPlanner.validateSelection(plan, input: trip, choices: choices, venues: venues, profile: profile)
        let stops = try plan.stops.map { stop -> ScheduledPlanningStop in
            guard let id = sourceToUI[stop.venueID] else { throw PlanningError.invalidResponse }
            let waiting = max(0, Int(stop.visitStart.timeIntervalSince(stop.arrival)))
            var value = ScheduledPlanningStop(id: id, name: stop.name, location: .init(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude),
                                              arrivalAt: stop.arrival, departureAt: stop.visitEnd,
                                              visitSeconds: Int(stop.visitEnd.timeIntervalSince(stop.visitStart)), travelSeconds: Int(ceil(stop.driveSeconds)),
                                              warnings: [stop.evidence, stop.weather] + (waiting > 0 ? ["Waiting before the visit: \(waiting / 60) minutes, within your allowed limit."] : []))
            value.visitStartsAt = stop.visitStart
            if let before = input.places.first(where: { $0.id == id })?.preferredBefore, stop.visitStart > before {
                value.warnings.append("Your preferred visit window may be missed; this destination was retained.")
            }
            return value
        }
        var evidence = [PlanningEvidence(id: "pocket-catalog", label: "Independent catalog", checkedAt: catalog.generatedAt,
                                         kind: "venue", summary: catalog.attribution, synthetic: synthetic)]
        if let weather = try await services.attribution() { evidence.append(weather) }
        var proposal = PlanProposal(id: plan.id, input: input, stops: stops, finishesAt: plan.finish, feasible: true,
                                    explanation: "Pocket Engine · local preference matching and schedule validation · Apple route estimates",
                                    warnings: warnings + plan.warnings, evidence: evidence, synthetic: synthetic)
        proposal.departureAt = plan.departure; proposal.returnTravelSeconds = options.returnToOrigin ? Int(ceil(plan.returnSeconds)) : nil
        if !input.preferences.isEmpty { proposal.warnings.append("Budget, popularity and other prose wishes are recorded, not verified guarantees.") }
        return .init(proposal: proposal, candidates: [], warnings: warnings + plan.warnings, synthetic: synthetic)
    }

    private static func profile(_ options: PlanningPreferences) throws -> Profile {
        var profile = Profile()
        for value in options.themes {
            guard let theme = PreferenceTheme(rawValue: value) else { throw PlanningError.invalidInput }
            profile.themes.insert(theme)
        }
        let known = Set(Interests.all)
        guard options.labels.isSubset(of: known) else { throw PlanningError.invalidInput }
        for label in options.labels {
            if let facet = Facet(rawValue: label), !facet.isCategoryLabel { profile.preferences[facet] = .liked }
            else { profile.categories.insert(Interests.canonical(label)) }
        }
        for (key, condition) in options.conditions {
            guard let facet = Facet(rawValue: key), let value = Preference(rawValue: condition.rawValue) else { throw PlanningError.invalidInput }
            profile.preferences[facet] = value
        }
        return profile
    }
    private static func fingerprint(_ request: PlanningRequest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard var object = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any] else { throw PlanningError.invalidInput }
        if let preferences = request.input.enginePreferences,
           var input = object["input"] as? [String: Any], var options = input["enginePreferences"] as? [String: Any] {
            options["themes"] = preferences.themes.sorted(); options["labels"] = preferences.labels.sorted()
            input["enginePreferences"] = options; object["input"] = input
        }
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }
    public nonisolated static func identity(_ sourceID: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(sourceID.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 15) | 128, bytes[7], (bytes[8] & 63) | 128, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func hasAvailabilityEvidence(_ venue: Venue) -> Bool {
        venue.hours?.fresh(at: .now) == true && venue.status(.publicAccess) == .supported
    }
    private static func place(_ venue: Venue) -> PlanningPlace {
        var value = PlanningPlace(id: identity(venue.id), name: venue.name,
                                  location: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude), visitSeconds: 2700)
        value.sourceID = venue.id; value.categories = venue.categories
        value.availabilityVerified = hasAvailabilityEvidence(venue)
        return value
    }

    public func planningJob(id: UUID) throws -> PlanningJob { guard let value = state.jobs[id] else { throw PlanningError.notFound }; return value }
    public func resumePlanning() -> PlanningJob? { state.pending.flatMap { state.jobs[$0] } }
    public func personalTrips() -> [PersonalPlanningTrip] { state.trips.values.sorted { $0.createdAt > $1.createdAt } }

    public func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) throws -> PersonalPlanningTrip {
        let fingerprint = Data("apply:\(jobID):\(expectedRevision.map(String.init) ?? "new")".utf8)
        if let receipt = state.receipts[requestID] {
            guard case .trip(let prior, let trip) = receipt, prior == fingerprint else { throw PlanningError.requestConflict }; return trip
        }
        if let applied = state.applied[jobID] {
            guard state.jobs[jobID]?.baseRevision == expectedRevision else { throw PlanningError.revisionConflict }
            var next = state; next.receipts[requestID] = .trip(fingerprint, applied)
            try commit(next); return applied
        }
        guard let job = state.jobs[jobID], job.baseRevision == expectedRevision, job.status == .succeeded,
              let proposal = job.result?.proposal, proposal.feasible else { throw PlanningError.invalidInput }
        guard Date().timeIntervalSince(job.createdAt) <= 900 else { throw PlanningError.expired }
        var trip: PersonalPlanningTrip
        if let id = job.tripID {
            guard var previous = state.trips[id], previous.revision == expectedRevision, previous.status != .completed else { throw PlanningError.revisionConflict }
            let visited = previous.plan.stops.filter { previous.completedStopIDs.contains($0.id) }
            previous.plan = proposal; previous.plan.stops = visited + proposal.stops; previous.revision += 1; trip = previous
        } else {
            trip = .init(id: UUID(), title: job.input.title, revision: 1, status: .planned, input: job.input,
                         plan: proposal, completedStopIDs: [], synthetic: synthetic, createdAt: .now)
        }
        var next = state
        next.trips[trip.id] = trip; next.applied[jobID] = trip; next.receipts[requestID] = .trip(fingerprint, trip); next.pending = nil
        try commit(next); return trip
    }

    public func recordEvent(tripID: UUID, event: C67Domain.PlanningEvent) throws -> PersonalPlanningTrip {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let fingerprint = try encoder.encode(event) + Data(tripID.uuidString.utf8)
        if let receipt = state.receipts[event.requestID] {
            guard case .trip(let prior, let trip) = receipt, prior == fingerprint else { throw PlanningError.requestConflict }; return trip
        }
        guard var trip = state.trips[tripID], trip.revision == event.expectedRevision, trip.status != .completed else { throw PlanningError.revisionConflict }
        let nextStop = trip.nextStop
        switch event.kind {
        case .start:
            guard trip.status == .planned else { throw PlanningError.invalidInput }; trip.status = .active
        case .arrive:
            guard trip.status == .active, trip.currentStopID == nil, nextStop?.id == event.stopID,
                  let index = trip.plan.stops.firstIndex(where: { $0.id == event.stopID }) else { throw PlanningError.invalidInput }
            trip.currentStopID = event.stopID; trip.currentArrivedAt = .now
            trip.plan.stops[index].departureAt = Date().addingTimeInterval(Double(trip.plan.stops[index].visitSeconds))
        case .completeStop:
            guard trip.status == .active, let nextStop, nextStop.id == event.stopID, trip.currentStopID == nextStop.id else { throw PlanningError.invalidInput }
            trip.completedStopIDs.append(nextStop.id); trip.currentStopID = nil; trip.currentArrivedAt = nil
            if trip.completedStopIDs.count == trip.plan.stops.count { trip.status = .completed }
        case .extendStay:
            guard trip.status == .active, nextStop?.id == event.stopID, trip.currentStopID == event.stopID,
                  let seconds = event.extraSeconds, (1 ... 7200).contains(seconds),
                  let index = trip.plan.stops.firstIndex(where: { $0.id == event.stopID }) else { throw PlanningError.invalidInput }
            trip.plan.stops[index].departureAt = max(Date(), trip.plan.stops[index].departureAt).addingTimeInterval(Double(seconds))
        }
        trip.revision += 1
        var next = state; next.trips[trip.id] = trip; next.receipts[event.requestID] = .trip(fingerprint, trip)
        try commit(next); return trip
    }

    private func commit(_ value: State) throws {
        if let storageURL {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
                try JSONEncoder().encode(value).write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
                try JSONEncoder().encode(value).write(to: storageURL, options: .atomic)
            #endif
        }
        state = value
    }
}
