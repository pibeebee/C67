import Foundation
import CryptoKit
import OSLog
import C67Domain
import PocketEngine

/// Persists native trips and integrates server ordering; legacy timed trips retain the local solver.
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
    private let services: PocketPlanningServices
    private let connection: any PocketConnectionProviding
    private let storageURL: URL?
    private let synthetic: Bool
    private var configurationRevision = 0
    private var orderTasks: [UUID: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: "io.pibeebee.c67", category: "pocket-planning")

    public init(services: PocketPlanningServices, connection: any PocketConnectionProviding, storageURL: URL?, synthetic: Bool = false) throws {
        self.services = services; self.connection = connection; self.storageURL = storageURL; self.synthetic = synthetic
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            var restored = try JSONDecoder().decode(State.self, from: Data(contentsOf: storageURL))
            for id in restored.jobs.keys where restored.jobs[id]?.status == .running && restored.jobs[id]?.input.enginePreferences?.reasonableOrdering != true {
                restored.jobs[id]?.status = .failed; restored.jobs[id]?.errorCode = "JOB_EXPIRED"
            }
            state = restored
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
    }

    public func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob {
        try request.input.validate(purpose: request.purpose)
        let fingerprint = try Self.fingerprint(request)
        if let receipt = state.receipts[request.requestID] {
            guard case .job(let prior, let id) = receipt, prior == fingerprint, let job = state.jobs[id] else { throw PlanningError.requestConflict }
            startOrdering(job)
            return state.jobs[id] ?? job
        }
        guard request.purpose != .firstItinerary || (request.tripID == nil && request.baseRevision == nil) else {
            throw PlanningError.invalidInput
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
                if input.enginePreferences?.automaticFirstPlan == true, input.enginePreferences?.returnToOrigin == true,
                   input.enginePreferences?.endPoint == nil {
                    input.enginePreferences?.endPoint = trip.input.origin
                }
                input.origin = current ? first.location : request.currentOrigin ?? trip.plan.stops.last(where: { trip.completedStopIDs.contains($0.id) })?.location ?? input.origin
                input.firstPlaceID = current ? first.id : nil
                input.places = remaining.compactMap { stop in
                    guard var place = trip.input.places.first(where: { $0.id == stop.id }) else { return nil }
                    if current && stop.id == first.id, let departure = stop.departureAt { place.visitSeconds = max(0, Int(ceil(departure.timeIntervalSinceNow))) }
                    return place
                }
                input.preservesPlaceOrder = true
            }
        }
        let usesOrdering = services.order != nil && (request.purpose == .firstItinerary || input.enginePreferences?.reasonableOrdering == true)
        if usesOrdering {
            if input.enginePreferences == nil { input.enginePreferences = PlanningPreferences() }
            input.enginePreferences?.reasonableOrdering = true
            input.enginePreferences?.allowsAIProcessing = true
            input.enginePreferences?.usesLuna = true
            if request.purpose == .firstItinerary {
                input.enginePreferences?.automaticFirstPlan = true
                input.enginePreferences?.returnToOrigin = true
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: input.timeZone)!
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
                input.startsAt = calendar.startOfDay(for: tomorrow)
                input.finishBy = input.startsAt.addingTimeInterval(86399)
            }
        }
        var job = PlanningJob(id: UUID(), status: .running, purpose: request.purpose, input: input,
                              tripID: request.tripID, baseRevision: request.baseRevision, result: nil, errorCode: nil, createdAt: .now)
        job.command = request
        var next = state
        next.jobs[job.id] = job; next.receipts[request.requestID] = .job(fingerprint, job.id); next.pending = job.id
        try commit(next)
        if usesOrdering {
            startOrdering(job)
            return job
        }
        let started = ContinuousClock.now
        let revision = configurationRevision
        do {
            let result = try await execute(input, purpose: request.purpose, requestID: request.requestID)
            try Task.checkCancellation()
            guard revision == configurationRevision else { throw CancellationError() }
            job.status = .succeeded; job.result = result
            if request.purpose == .firstItinerary, let proposal = result.proposal {
                job.originalInput = input; job.input = proposal.input
            }
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

    private func execute(_ input: PlanningInput, purpose: PlanningPurpose, requestID: UUID) async throws -> PlanningResult {
        if input.enginePreferences?.reasonableOrdering == true, let order = services.order {
            let result = try await order(input, requestID).validated(for: input)
            let places = Dictionary(uniqueKeysWithValues: input.places.map { ($0.id, $0) })
            let stops = result.orderedIDs.compactMap { id -> ScheduledPlanningStop? in
                guard let place = places[id], let suggestion = result.stop(id) else { return nil }
                let seconds = place.durationOverridden == true ? place.visitSeconds : suggestion.duration?.suggestedSeconds ?? 0
                return .init(id: id, name: place.name, location: place.location, arrivalAt: nil, departureAt: nil,
                             visitSeconds: seconds, travelSeconds: 0, warnings: suggestion.uncertainties)
            }
            let evidence = result.weatherSources.map { source in
                PlanningEvidence(id: source.id, label: source.source, url: source.url, checkedAt: source.checkedAt,
                                 kind: "weather", summary: source.coverage, synthetic: synthetic)
            }
            var proposal = PlanProposal(id: UUID(), input: input, stops: stops, finishesAt: nil, feasible: true,
                                        explanation: result.tripRationale, warnings: result.tradeoffs + result.uncertainties + result.contextWarnings,
                                        evidence: evidence, synthetic: synthetic)
            proposal.experiencePlan = result; proposal.firstItinerary = true
            let routed = try await calculateExperienceRoute(proposal)
            return .init(proposal: routed, candidates: [], warnings: result.contextWarnings, synthetic: synthetic)
        }
        guard let options = input.enginePreferences, input.timeZone == "Asia/Jakarta" else {
            throw PlanningError.invalidInput
        }
        if purpose != .firstItinerary, !options.allowsAIProcessing {
            throw EngineError.invalid("Allow Luna processing before requesting advice.")
        }
        guard purpose != .suggest else {
            throw EngineError.invalid("Choose places from search before requesting visit research.")
        }
        guard let resolve = services.resolve else {
            throw EngineError.invalid("The visit research service is not configured.")
        }
        let research = try await resolve(input, requestID)
        _ = try PocketAdviceSelection(slotID: "", requestedModel: research.requestedModel, reportedModel: research.reportedModel, reportedReasoningEffort: research.reportedReasoningEffort, providerProtocol: research.providerProtocol).validated()
        guard research.records.count == input.places.count,
              Set(research.records.map(\.placeID)) == Set(input.places.map(\.id)) else { throw PlanningError.invalidResponse }
        guard research.records.allSatisfy({ record in
            guard ["ready", "conditional", "unresolved"].contains(record.status) else { return false }
            if record.status == "unresolved" { return record.venue == nil }
            return record.venue != nil && record.recommendedMinutes.map { (15 ... 240).contains($0) } == true
        }) else { throw PlanningError.invalidResponse }
        let snapshot = Catalog(schemaVersion: 1, generatedAt: research.resolvedAt,
                               attribution: "Current web sources researched for the selected branches with Luna.",
                               venues: research.records.compactMap(\.venue))
        let catalog = try snapshot.validated()
        let pool = catalog.venues
        let profile = try Self.profile(options)
        var warnings: [String] = []
        var input = input
        for index in input.places.indices {
            guard let record = research.records.first(where: { $0.placeID == input.places[index].id }) else {
                throw PlanningError.invalidResponse
            }
            input.places[index].categories = record.venue?.categories ?? input.places[index].categories
            if purpose == .firstItinerary, let minutes = record.recommendedMinutes, (15 ... 240).contains(minutes) {
                input.places[index].visitSeconds = minutes * 60
            }
        }
        if purpose == .firstItinerary {
            return try await firstItinerary(input, options: options, catalog: catalog, pool: pool,
                                            profile: profile, warnings: warnings, research: research)
        }
        guard !input.places.isEmpty else { throw PlanningError.invalidInput }
        var venues: [Venue] = []
        var choices: [StopChoice] = []
        var sourceToUI: [String: UUID] = [:]
        for place in input.places {
            let point = Coordinate(latitude: place.location.latitude, longitude: place.location.longitude)
            let candidates = Self.matching(place, in: pool)
            guard candidates.count <= 1 else { throw EngineError.invalid("A place matches multiple branches. Select its exact location again.") }
            let venue = candidates.first ?? Venue(id: "selected-" + place.id.uuidString, name: place.name, branch: place.name, address: "", coordinate: point,
                                                  categories: place.categories, license: "Traveller-selected place · current session")
            guard sourceToUI[venue.id] == nil else { throw EngineError.invalid("Select distinct destinations.") }
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
                             preservesOrder: input.preservesPlaceOrder, firstVenueID: first, endPoint: options.endPoint.map(Self.coordinate))
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
            guard options.allowsAIProcessing else { throw EngineError.invalid("Allow selected-place research and schedule reasoning with Luna Max.") }
            let menu = VisitAdviceRequest(plans: plans, venues: venues, profile: profile, choices: choices)
            let adviceStarted = ContinuousClock.now
            let advice = try await services.advise(menu).validated()
            plan = try menu.selected(advice.slotID, from: plans)
            logger.info("luna_selected slot=\(advice.slotID, privacy: .public) elapsed=\(String(describing: adviceStarted.duration(to: .now)), privacy: .public)")
            warnings.append("Luna Max selected a validated schedule option; Apple supplied the route times.")
        } else { plan = plans[0]; warnings.append("Luna researched the visit evidence; the on-device planner selected the schedule.") }
        try Task.checkCancellation()
        try ItineraryPlanner.validateSelection(plan, input: trip, choices: choices, venues: venues, profile: profile)
        return try await proposal(for: plan, input: input, sourceToUI: sourceToUI, catalog: catalog, warnings: warnings, research: research)
    }

    private static func coordinate(_ point: PlanningPoint) -> Coordinate {
        .init(latitude: point.latitude, longitude: point.longitude)
    }

    private static func matching(_ place: PlanningPlace, in pool: [Venue]) -> [Venue] {
        let exact = pool.filter { $0.id == place.sourceID || UUID(uuidString: $0.id) == place.id || Self.identity($0.id) == place.id }
        if !exact.isEmpty { return exact }
        let point = coordinate(place.location)
        let name = CandidatePool.normalizedName(place.name)
        return pool.filter { venue in
            venue.coordinate.distance(to: point) <= 125
                && ([venue.name] + venue.aliases).contains { CandidatePool.normalizedName($0) == name }
        }
    }

    private struct FirstCandidate: Sendable {
        var place: PlanningPlace
        let venue: Venue
    }

    private func firstItinerary(_ request: PlanningInput, options: PlanningPreferences, catalog: Catalog,
                                pool: [Venue], profile: Profile, warnings: [String], research: PocketVisitResolution) async throws -> PlanningResult {
        let calendar = TripClock.calendar
        let now = Date()
        let confirmedDay = request.places.compactMap(\.visitConfirmation?.opensAt)
            .first { $0 >= calendar.startOfDay(for: now) }
        let upcoming = (1 ... 7).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        var days: [Date] = []
        if let confirmedDay { days.append(calendar.startOfDay(for: confirmedDay)) }
        days += upcoming.map { calendar.startOfDay(for: $0) }
        days = days.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }

        var omitted: [UUID: String] = [:]
        var confirmable: Set<UUID> = []
        var candidates: [FirstCandidate] = []
        var seen: Set<String> = []
        let sorted = request.places.sorted {
            ($0.id == options.mainSpotID ? 0 : 1) < ($1.id == options.mainSpotID ? 0 : 1)
        }
        for var place in sorted {
            let matches = Self.matching(place, in: pool)
            guard matches.count <= 1 else { omitted[place.id] = "Several branches match this selection."; continue }
            guard let venue = matches.first ?? (place.visitConfirmation?.publicAccessConfirmed == true
                ? Venue(id: "selected-" + place.id.uuidString, name: place.name, branch: place.name, address: "",
                        coordinate: Self.coordinate(place.location), categories: place.categories, license: "Trip-specific confirmation")
                : nil) else {
                omitted[place.id] = research.records.first { $0.placeID == place.id }?.reason
                    ?? "Visit information is still unresolved after web research."
                continue
            }
            guard seen.insert(venue.id).inserted else { omitted[place.id] = "Already selected as the same branch."; continue }
            let isConfirmed = place.visitConfirmation?.publicAccessConfirmed == true
            if !isConfirmed, venue.hours?.fresh(at: now) == true, venue.hours?.reservationRequired == true {
                omitted[place.id] = research.records.first { $0.placeID == place.id }?.reason
                    ?? "A reservation must be confirmed first."
                confirmable.insert(place.id)
                continue
            }
            guard isConfirmed || (venue.hours?.fresh(at: now) == true && venue.status(.publicAccess, at: now) == .supported) else {
                omitted[place.id] = venue.hours?.conflictingSources?.isEmpty == false
                    ? "Published opening hours disagree."
                    : "Opening hours or public access could not be verified."
                confirmable.insert(place.id)
                continue
            }
            let duration = place.visitSeconds / 60
            if let hours = venue.hours, hours.fresh(at: now), let maximum = hours.maximumVisitMinutes {
                guard maximum >= 15 else { omitted[place.id] = "The supported visit is shorter than the planner can schedule."; continue }
                place.visitSeconds = min(duration, maximum) * 60
            } else { place.visitSeconds = duration * 60 }
            candidates.append(.init(place: place, venue: venue))
        }

        let services = self.services
        var best: (plan: Itinerary, trip: TripInput, candidates: [FirstCandidate])?
        var evaluated: Set<UUID> = []
        var attemptedRouting = false
        var providerThrottled = false
        var alternatives: [(plan: Itinerary, trip: TripInput, candidates: [FirstCandidate])] = []
        for day in days {
            try Task.checkCancellation()
            let start = max(day.addingTimeInterval(6 * 3600), now.addingTimeInterval(10 * 60))
            let end = day.addingTimeInterval(24 * 3600 - 60)
            guard start < end else { continue }
            let ready = candidates.compactMap { item -> (FirstCandidate, StopChoice)? in
                let manual = item.place.visitConfirmation.flatMap { value -> TripOverride? in
                    let open = Int(ceil(value.opensAt.timeIntervalSince(day) / 60))
                    let close = Int(floor(value.closesAt.timeIntervalSince(day) / 60))
                    guard value.publicAccessConfirmed, open >= 0, close <= 1440, close > open else { return nil }
                    return .init(day: TripClock.day(day), opens: open, closes: close, publicAccessConfirmed: true)
                }
                let venue = item.venue
                if venue.hours?.fresh(at: start) == true, venue.hours?.closedDates?.contains(TripClock.day(day)) == true {
                    return nil
                }
                guard manual != nil || (venue.hours?.fresh(at: start) == true && venue.hours?.reservationRequired != true
                    && !((venue.hours?.windows(on: day) ?? []).isEmpty) && venue.status(.publicAccess, at: start) == .supported) else { return nil }
                let timing = research.records.first { $0.placeID == item.place.id }?.preferredMinute.map(VisitTiming.preferred)
                return (item, .init(venueID: venue.id, required: false, durationMinutes: item.place.visitSeconds / 60,
                                    override: manual, timing: timing))
            }
            evaluated.formUnion(ready.map { $0.0.place.id })
            let shortlist = ready.prefix(12)
            guard !shortlist.isEmpty else { continue }
            attemptedRouting = true
            let choices = shortlist.map { $0.1 }, items = shortlist.map { $0.0 }, venues = items.map(\.venue)
            let main = items.first { $0.place.id == options.mainSpotID }?.venue.id
            let trip = TripInput(departure: start, deadline: end, origin: Self.coordinate(request.origin),
                                 returnToOrigin: true, maxWaitMinutes: 45, avoidRain: options.avoidRain,
                                 latestDeparture: end, minimumStops: 1,
                                 maximumStops: min(6, shortlist.count), endPoint: options.endPoint.map(Self.coordinate),
                                 preferredVenueID: main, automaticTiming: true)
            do {
                let plan = try await ItineraryPlanner.make(input: trip, choices: choices, venues: venues, profile: profile,
                                                           travel: { try await services.travel($0, $1, $2, .automobile) }, weather: services.weather, budget: 120)
                try ItineraryPlanner.validateSelection(plan, input: trip, choices: choices, venues: venues, profile: profile)
                providerThrottled = plan.providerThrottled == true
                alternatives.append((plan, trip, items))
                if let previous = best {
                    let includes = plan.stops.contains { $0.venueID == main }
                    let incumbent = previous.plan.stops.contains { $0.venueID == previous.trip.preferredVenueID }
                    let betterCoverage = plan.stops.count > previous.plan.stops.count
                    let sameCoverage = plan.stops.count == previous.plan.stops.count
                    let shorter = plan.finish.timeIntervalSince(plan.departure) < previous.plan.finish.timeIntervalSince(previous.plan.departure)
                    if includes != incumbent ? includes : (betterCoverage || (sameCoverage && shorter)) {
                        best = (plan, trip, items)
                    }
                } else {
                    best = (plan, trip, items)
                }
            } catch TravelQuoteError.throttled {
                providerThrottled = true
                break
            } catch is EngineError {
                try Task.checkCancellation()
            }
            if providerThrottled { break }
        }

        var lunaReason: String?
        if !alternatives.isEmpty {
            let mainID = options.mainSpotID?.uuidString.lowercased()
            let keepsMain = alternatives.contains { option in
                option.plan.stops.contains { $0.venueID.lowercased() == mainID }
            }
            if keepsMain {
                alternatives = alternatives.filter { option in option.plan.stops.contains { $0.venueID.lowercased() == mainID } }
            }
            let coverage = alternatives.map { $0.plan.stops.count }.max() ?? 0
            alternatives = alternatives.filter { $0.plan.stops.count == coverage }
            var menu = VisitAdviceRequest(plans: alternatives.map(\.plan), venues: pool, profile: profile)
            menu.day = nil
            menu.userPreferences = request.preferences
            menu.mainSpotID = options.mainSpotID?.uuidString
            let advice = try await services.advise(menu).validated()
            guard let index = menu.options.firstIndex(where: { $0.slotID == advice.slotID }), alternatives.indices.contains(index) else {
                throw PlanningError.invalidResponse
            }
            let selected = alternatives[index]
            let choices = selected.candidates.map { item in
                StopChoice(venueID: item.venue.id, required: false, durationMinutes: item.place.visitSeconds / 60,
                           override: item.place.visitConfirmation.map { value in
                               TripOverride(day: TripClock.day(selected.trip.departure),
                                            opens: Int(value.opensAt.timeIntervalSince(calendar.startOfDay(for: selected.trip.departure)) / 60),
                                            closes: Int(value.closesAt.timeIntervalSince(calendar.startOfDay(for: selected.trip.departure)) / 60),
                                            publicAccessConfirmed: value.publicAccessConfirmed)
                           })
            }
            try ItineraryPlanner.validateSelection(selected.plan, input: selected.trip, choices: choices,
                                                   venues: selected.candidates.map(\.venue), profile: profile)
            best = selected
            lunaReason = advice.explanation
        }

        var checkedInSolver: Set<UUID> = []
        if let best { checkedInSolver.formUnion(best.candidates.map(\.place.id)) }
        for place in request.places where omitted[place.id] == nil {
            if !evaluated.contains(place.id) {
                omitted[place.id] = "No verified opening window on the dates checked."
            } else if attemptedRouting {
                omitted[place.id] = checkedInSolver.contains(place.id)
                    ? "No feasible visit was found in the route options checked."
                    : "No visit was scheduled among the options checked."
            }
        }
        guard let best else {
            var reasons = request.places.compactMap { place in omitted[place.id].map { "\(place.name): \($0)" } }
            if attemptedRouting {
                let message = providerThrottled
                    ? "Apple Maps limited route requests. Try again in a moment."
                    : "No complete route could be validated. Try again to refresh route estimates."
                reasons.insert(message, at: 0)
            }
            return .init(candidates: request.places.filter { confirmable.contains($0.id) },
                         warnings: reasons, synthetic: synthetic)
        }
        let sourceToUI = Dictionary(uniqueKeysWithValues: best.candidates.map { ($0.venue.id, $0.place.id) })
        let included = Set(best.plan.stops.compactMap { sourceToUI[$0.venueID] })
        let notScheduled = request.places.filter { !included.contains($0.id) }.compactMap { place in
            omitted[place.id].map { "\(place.name): \($0)" }
        }
        var selected = request
        selected.startsAt = best.plan.departure
        selected.finishBy = best.trip.deadline
        selected.mode = .automobile
        selected.firstPlaceID = nil
        selected.preservesPlaceOrder = false
        selected.places = best.candidates.map(\.place).filter { included.contains($0.id) }
        selected.enginePreferences?.automaticFirstPlan = true
        selected.enginePreferences?.returnToOrigin = true
        selected.enginePreferences?.maximumWaitMinutes = 45
        selected.enginePreferences?.flexibleDeparture = false
        selected.enginePreferences?.usesLuna = true
        selected.enginePreferences?.allowsAIProcessing = true
        let providerWarnings = providerThrottled ? ["Apple Maps limited route requests. Some dates could not be checked."] : []
        var result = try await proposal(for: best.plan, input: selected, sourceToUI: sourceToUI, catalog: catalog,
                                        warnings: warnings + providerWarnings, research: research)
        let dayType = calendar.isDateInWeekend(best.plan.departure) ? "weekend" : "weekday"
        let mainIncluded = best.plan.stops.contains { $0.venueID == best.trip.preferredVenueID }
        let stopCount = best.plan.stops.count
        let reason = "The suggested \(dayType) plan fits \(stopCount) " + (stopCount == 1 ? "visit" : "visits")
            + (mainIncluded ? ", including your main spot" : "") + ", with a route to your end point."
        result.proposal?.explanation = reason + (lunaReason.map { " " + $0 } ?? "")
        result.proposal?.warnings.append("Visit durations and activity timing were suggested by Luna from the retrieved evidence. Routine hours do not guarantee date-specific exceptions or reservation availability.")
        result.proposal?.firstItinerary = true
        result.proposal?.unscheduledPlaces = notScheduled
        return result
    }

    private func proposal(for plan: Itinerary, input: PlanningInput, sourceToUI: [String: UUID],
                          catalog: Catalog, warnings: [String], research: PocketVisitResolution) async throws -> PlanningResult {
        let stops = try plan.stops.map { stop -> ScheduledPlanningStop in
            guard let id = sourceToUI[stop.venueID] else { throw PlanningError.invalidResponse }
            let waiting = max(0, Int(stop.visitStart.timeIntervalSince(stop.arrival)))
            var value = ScheduledPlanningStop(id: id, name: stop.name, location: .init(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude),
                                              arrivalAt: stop.arrival, departureAt: stop.visitEnd,
                                              visitSeconds: Int(stop.visitEnd.timeIntervalSince(stop.visitStart)), travelSeconds: Int(ceil(stop.driveSeconds)),
                                              warnings: [stop.evidence, stop.weather] + (waiting > 0 ? ["Waiting before the visit: \(waiting / 60) minutes, within your allowed limit."] : []))
            value.visitStartsAt = stop.visitStart
            if let reason = research.records.first(where: { $0.placeID == id })?.recommendationReason, !reason.isEmpty {
                value.warnings.append("Suggested visit timing • " + reason)
            }
            if let before = input.places.first(where: { $0.id == id })?.preferredBefore, stop.visitStart > before {
                value.warnings.append("Your preferred visit window may be missed; this destination was retained.")
            }
            return value
        }
        var evidence = [PlanningEvidence(id: "visit-research", label: "Web visit research and Luna", checkedAt: catalog.generatedAt,
                                         kind: "venue", summary: catalog.attribution, synthetic: synthetic)]
        for venue in catalog.venues where plan.stops.contains(where: { $0.venueID == venue.id }) {
            if let hours = venue.hours, let url = URL(string: hours.sourceURL) {
                evidence.append(.init(id: "hours-" + venue.id, label: venue.name + " • opening hours", url: url,
                                      checkedAt: hours.checkedAt, kind: "venue", summary: hours.quote, synthetic: synthetic))
            }
            for fact in venue.facts where fact.field == .publicAccess {
                evidence.append(.init(id: "access-" + venue.id, label: venue.name + " • visitor entry", url: URL(string: fact.sourceURL),
                                      checkedAt: fact.checkedAt, kind: "venue", summary: fact.quote, synthetic: synthetic))
            }
        }
        if let weather = try await services.attribution() { evidence.append(weather) }
        var proposal = PlanProposal(id: plan.id, input: input, stops: stops, finishesAt: plan.finish, feasible: true,
                                    explanation: "Pocket Engine · local preference matching and schedule validation · Apple route estimates",
                                    warnings: warnings + plan.warnings, evidence: evidence, synthetic: synthetic)
        proposal.departureAt = plan.departure; proposal.returnTravelSeconds = input.enginePreferences?.returnToOrigin == true ? Int(ceil(plan.returnSeconds)) : nil
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

    private func startOrdering(_ job: PlanningJob) {
        guard job.status == .running, job.input.enginePreferences?.reasonableOrdering == true,
              orderTasks[job.id] == nil, let command = job.command else { return }
        state.jobs[job.id]?.errorCode = nil
        let revision = configurationRevision
        orderTasks[job.id] = Task { await self.finishOrdering(job.id, requestID: command.requestID, revision: revision) }
    }

    private func finishOrdering(_ id: UUID, requestID: UUID, revision: Int) async {
        defer { orderTasks[id] = nil }
        guard var job = state.jobs[id] else { return }
        do {
            let result = try await execute(job.input, purpose: job.purpose, requestID: requestID)
            guard revision == configurationRevision else { throw CancellationError() }
            job.status = .succeeded; job.result = result; job.errorCode = nil
            job.originalInput = job.command?.input
        } catch {
            let planningError = error as? PlanningError
            if planningError == .unavailable || error is CancellationError {
                job.status = .running; job.errorCode = "ORDER_CONNECTION_INTERRUPTED"
            } else {
                job.status = .failed
                if case .failed(let code) = planningError { job.errorCode = code }
                else if planningError == .invalidResponse || error is DecodingError { job.errorCode = "ORDER_RESPONSE_INVALID" }
                else { job.errorCode = "ORDER_GENERATION_FAILED" }
            }
            logger.notice("Pocket order \(requestID.uuidString, privacy: .public): \(job.errorCode ?? "unknown", privacy: .public)")
        }
        var next = state; next.jobs[id] = job
        do { try commit(next) } catch { logger.error("Could not persist ordering status") }
    }

    public func planningJob(id: UUID) throws -> PlanningJob {
        guard let value = state.jobs[id] else { throw PlanningError.notFound }
        if value.errorCode == "ORDER_CONNECTION_INTERRUPTED" { throw PlanningError.unavailable }
        startOrdering(value)
        return state.jobs[id] ?? value
    }
    public func resumePlanning() -> PlanningJob? {
        guard let value = state.pending.flatMap({ state.jobs[$0] }) else { return nil }
        startOrdering(value)
        return state.jobs[value.id] ?? value
    }

    public func renameProposal(jobID: UUID, title: String) async throws -> PlanningJob {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120, var job = state.jobs[jobID], job.status == .succeeded,
              job.result?.proposal?.experiencePlan != nil, state.applied[jobID] == nil else { throw PlanningError.invalidInput }
        job.input.title = title; job.result?.proposal?.input.title = title
        var next = state; next.jobs[jobID] = job; try commit(next)
        return job
    }
    public func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob {
        guard let original = state.jobs[jobID], original.status == .succeeded, var proposal = original.result?.proposal,
              proposal.experiencePlan != nil, state.applied[jobID] == nil else { throw PlanningError.invalidInput }
        if let departure {
            guard let zone = TimeZone(identifier: proposal.input.timeZone) else { throw PlanningError.invalidInput }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            if !calendar.isDate(departure, inSameDayAs: proposal.input.startsAt) {
                let oldDay = calendar.startOfDay(for: proposal.input.startsAt)
                let newDay = calendar.startOfDay(for: departure)
                guard let days = calendar.dateComponents([.day], from: oldDay, to: newDay).day,
                      let start = calendar.date(byAdding: .day, value: days, to: proposal.input.startsAt),
                      let finish = calendar.date(byAdding: .day, value: days, to: proposal.input.finishBy) else { throw PlanningError.invalidInput }
                proposal.input.startsAt = start
                proposal.input.finishBy = finish
            }
            proposal.departureAt = departure
        }
        if let orderedIDs {
            let stops = Dictionary(uniqueKeysWithValues: proposal.stops.map { ($0.id, $0) })
            let places = Dictionary(uniqueKeysWithValues: proposal.input.places.map { ($0.id, $0) })
            guard orderedIDs.count == stops.count, Set(orderedIDs) == Set(stops.keys), Set(orderedIDs) == Set(places.keys) else {
                throw PlanningError.invalidInput
            }
            proposal.stops = orderedIDs.compactMap { stops[$0] }
            proposal.input.places = orderedIDs.compactMap { places[$0] }
            proposal.input.preservesPlaceOrder = true
        }
        let routed = try await calculateExperienceRoute(proposal, reusing: orderedIDs == nil ? nil : original.result?.proposal)
        guard state.jobs[jobID] == original, state.applied[jobID] == nil else { throw PlanningError.revisionConflict }
        var job = original
        job.input = routed.input
        job.result?.proposal = routed
        var next = state; next.jobs[jobID] = job; try commit(next)
        return job
    }

    public func refreshExperienceRoute(tripID: UUID) async throws -> PersonalPlanningTrip {
        guard let original = state.trips[tripID], original.status == .planned,
              original.plan.experiencePlan != nil else { throw PlanningError.invalidInput }
        let routed = try await calculateExperienceRoute(original.plan)
        guard state.trips[tripID] == original else { throw PlanningError.revisionConflict }
        var trip = original
        trip.plan = routed
        trip.revision += 1
        var next = state; next.trips[tripID] = trip; try commit(next)
        return trip
    }

    private func calculateExperienceRoute(_ proposal: PlanProposal, reusing previous: PlanProposal? = nil) async throws -> PlanProposal {
        guard var clock = proposal.estimatedExperienceDeparture else { return proposal }
        let started = ContinuousClock.now
        var routed = proposal
        var origin = proposal.input.origin
        var throttled = false
        let reusable: [UUID: (origin: PlanningPoint, stop: ScheduledPlanningStop)]
        if let previous, let checked = previous.experienceRouteCheckedAt, Date().timeIntervalSince(checked) < 300 {
            let estimates = previous.stopsWithExperienceEstimates
            reusable = Dictionary(uniqueKeysWithValues: estimates.enumerated().map { index, stop in
                (stop.id, (index == 0 ? previous.input.origin : estimates[index - 1].location, stop))
            })
        } else { reusable = [:] }
        for index in routed.stops.indices {
            try Task.checkCancellation()
            var stop = routed.stops[index]
            stop.travelSeconds = 0
            stop.roadDistanceMeters = nil
            if origin == stop.location {
                stop.roadDistanceMeters = 0
            } else if let prior = reusable[stop.id], prior.origin == origin, prior.stop.location == stop.location,
                      let meters = prior.stop.roadDistanceMeters,
                      prior.stop.arrivalAt?.addingTimeInterval(-Double(prior.stop.travelSeconds)) == clock {
                stop.travelSeconds = prior.stop.travelSeconds
                stop.roadDistanceMeters = meters
            } else if !throttled {
                do {
                    let quote = try await services.travel(Self.coordinate(origin), Self.coordinate(stop.location), max(clock, .now), .automobile)
                    if quote.seconds.isFinite, (0 ... 604_800).contains(quote.seconds), quote.meters.isFinite, quote.meters >= 0 {
                        stop.travelSeconds = Int(quote.seconds.rounded(.up))
                        stop.roadDistanceMeters = quote.meters
                    }
                } catch TravelQuoteError.throttled { throttled = true }
                catch { try Task.checkCancellation() }
            }
            routed.stops[index] = stop
            origin = stop.location
            clock = clock.addingTimeInterval(Double(stop.experienceTravelSeconds + stop.experienceVisitSeconds))
        }
        try Task.checkCancellation()
        routed.experienceRouteCheckedAt = .now
        let quoted = routed.stops.filter { $0.roadDistanceMeters != nil }.count
        logger.info("experience_route quoted=\(quoted) legs=\(routed.stops.count) elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
        return routed
    }

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
        guard proposal.experiencePlan != nil || Date().timeIntervalSince(job.createdAt) <= 900 else { throw PlanningError.expired }
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
            let seconds = trip.plan.stops[index].visitSeconds
            trip.plan.stops[index].departureAt = trip.plan.experiencePlan != nil && seconds == 0 ? nil : Date().addingTimeInterval(Double(seconds))
        case .completeStop:
            guard trip.status == .active, let nextStop, nextStop.id == event.stopID, trip.currentStopID == nextStop.id else { throw PlanningError.invalidInput }
            trip.completedStopIDs.append(nextStop.id); trip.currentStopID = nil; trip.currentArrivedAt = nil
            if trip.completedStopIDs.count == trip.plan.stops.count { trip.status = .completed }
        case .extendStay:
            guard trip.status == .active, nextStop?.id == event.stopID, trip.currentStopID == event.stopID,
                  let seconds = event.extraSeconds, (1 ... 7200).contains(seconds),
                  let index = trip.plan.stops.firstIndex(where: { $0.id == event.stopID }) else { throw PlanningError.invalidInput }
            trip.plan.stops[index].departureAt = max(Date(), trip.plan.stops[index].departureAt ?? Date()).addingTimeInterval(Double(seconds))
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
