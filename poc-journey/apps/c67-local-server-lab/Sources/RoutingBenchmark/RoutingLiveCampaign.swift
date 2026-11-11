import Foundation
import PlaceContextEngine
import TripIntegration

@MainActor public enum RoutingLiveCampaign {
    public static func run(manifest: RoutingManifest, environment env: [String: String], probe: Bool) async throws -> [RoutingObservation] {
        try manifest.validate()
        let budget = try RoutingBudget()
        let googleEnabled = env["ROUTING_GOOGLE_LIVE"] == "1"
        var google: GoogleRoutingProvider?
        if googleEnabled, let key = env["GOOGLE_ROUTES_API_KEY"] { google = try GoogleRoutingProvider(key: key, budget: budget) }
        var apple = try? AppleRoutingProvider.configured(environment: env)
        let valhalla = try env["VALHALLA_BASE_URL"].flatMap(URL.init(string:)).map { try ValhallaRoutingProvider(baseURL: $0) }
        var output: [RoutingObservation] = []
        let now = Date(), departure = Date().addingTimeInterval(300)
        var venues = manifest.venues
        var snapshots: [String: PlaceSnapshot] = [:]
        if !probe, let acquisition = google {
            let acquisitionClock = ContinuousClock.now
            for index in venues.indices {
                do {
                    if venues[index].googlePlaceID == nil { venues[index].googlePlaceID = try await acquisition.resolve(venues[index]) }
                    if let id = venues[index].googlePlaceID {
                        let details = try await acquisition.snapshot(placeID: id, now: .now)
                        snapshots[venues[index].id] = details.snapshot
                        // Record coverage counts, never the coordinates or provider response.
                        output.append(row(venues[index].id, backend: .googlePlaceID, mode: .walking, repetition: 0, probe: false, outcome: "identity_resolved", seconds: 0, calls: 0, access: "provider_entrances_\(details.entrances)_navigation_points_\(details.navigationPoints)_not_field_verified"))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let error as RoutingFailure {
                    if [.budgetExhausted, .authentication, .throttled].contains(error) {
                        output.append(row("acquisition", backend: .googlePlaceID, mode: .walking, repetition: 0, probe: false, outcome: error.rawValue, seconds: 0, calls: budget.requests, access: "unverified"))
                        google = nil; break
                    }
                } catch { /* An unresolved identity remains unavailable; no approximate replacement. */ }
            }
            output.append(row("acquisition_summary", backend: .googlePlaceID, mode: .walking, repetition: 0, probe: false, outcome: "acquisition_completed", seconds: RoutingFixtures.seconds(acquisitionClock), calls: budget.requests, access: "identity_and_entrance_coverage_only"))
        }
        for (index, venue) in venues.enumerated() {
            // Rotate variant order, not provider data or ground-truth references.
            let variants = RouteBackend.allCases
            let offset = index % variants.count
            let rotated = Array(variants[offset...]) + Array(variants[..<offset])
            variantLoop: for backend in rotated where !probe || backend == .valhallaAccess {
                let provider: (any RoutingProvider)?
                switch backend { case .applePin, .appleAccess: provider = apple; case .googlePlaceID: provider = google; case .valhallaAccess: provider = valhalla }
                for mode in RouteMode.allCases {
                    for repetition in 0 ..< 3 {
                        let clock = ContinuousClock.now, before = budget.requests
                        var outcome = "missing_configuration", access = "unverified", calls = 0
                        do {
                            if backend == .googlePlaceID && !googleEnabled { throw RoutingFailure.disabledByScope }
                            guard let provider else { throw RoutingFailure.missingConfiguration }
                            let target: RoutingEndpoint
                            let source: RoutingEndpoint
                            if probe {
                                // Explicit POI-coordinate diagnostic; never counted as entrance routing.
                                target = .init(id: venue.id, revision: "osm-poi-unverified", point: venue.displayPoint)
                                let previous = venues[(index + venues.count - 1) % venues.count]
                                source = .init(id: previous.id, revision: "osm-poi-unverified", point: previous.displayPoint)
                            } else {
                                target = try venue.endpoint(backend: backend, mode: mode, now: now)
                                guard let origin = venues.first(where: { $0.id != venue.id }) else { throw RoutingFailure.invalidInput }
                                source = try origin.endpoint(backend: backend, mode: mode, now: now)
                            }
                            calls = 1
                            let query = RoutingQuery(from: source, to: target, mode: mode, departure: departure, geometry: true)
                            let result = try await provider.route(query)
                            outcome = result == nil ? "unavailable" : "available"
                            if let result { access = probe ? "poi_probe_not_entrance_validation" : AccessEvaluation.status(venue: venue, result: result, selectionSource: venue.accesses.first?.sourceURL) }
                        } catch is CancellationError { throw CancellationError() }
                        catch let error as RoutingFailure {
                            outcome = error.rawValue
                            if [.authentication, .throttled, .budgetExhausted].contains(error) {
                                output.append(row(venue.id, backend: backend, mode: mode, repetition: repetition, probe: probe, outcome: outcome, seconds: RoutingFixtures.seconds(clock), calls: backend == .googlePlaceID ? budget.requests - before : calls, access: access))
                                if backend == .googlePlaceID { google = nil }
                                if backend == .applePin || backend == .appleAccess { apple = nil }
                                continue variantLoop
                            }
                        } catch { outcome = "provider_failure" }
                        output.append(row(venue.id, backend: backend, mode: mode, repetition: repetition, probe: probe, outcome: outcome, seconds: RoutingFixtures.seconds(clock), calls: backend == .googlePlaceID ? budget.requests - before : calls, access: access))
                    }
                }
            }
        }
        if !probe {
            output += try await itineraries(venues: venues, snapshots: snapshots, google: google, apple: apple, valhalla: valhalla, budget: budget, departure: departure, googleEnabled: googleEnabled)
        }
        return output
    }
    private static func itineraries(venues: [RoutingVenue], snapshots: [String: PlaceSnapshot], google: GoogleRoutingProvider?, apple: AppleRoutingProvider?, valhalla: ValhallaRoutingProvider?, budget: RoutingBudget, departure: Date, googleEnabled: Bool) async throws -> [RoutingObservation] {
        var rows: [RoutingObservation] = []
        let selected = Array(venues.prefix(7))
        backendLoop: for backend in RouteBackend.allCases {
            let base: (any RoutingProvider)?
            switch backend { case .applePin, .appleAccess: base = apple; case .googlePlaceID: base = google; case .valhallaAccess: base = valhalla }
            for count in [1, 3, 6] {
                for transit in [false, true] {
                    for policy in ["baseline", "finalists"] {
                        let clock = ContinuousClock.now
                        let requestsBefore = budget.requests
                        var activeMemo: RoutingMemo?
                        let id = "itinerary-\(count)-\(transit ? "tj" : "car")"
                        do {
                            if backend == .googlePlaceID && !googleEnabled { throw RoutingFailure.disabledByScope }
                            guard let base, selected.count > count else { throw RoutingFailure.missingConfiguration }
                            let candidates = Array(selected.prefix(count + 1))
                            var endpoints: [String: RoutingEndpoint] = [:], points: [String: RoutingPoint] = [:]
                            var stops: [ContextPlanStop] = []
                            for (index, venue) in candidates.enumerated() {
                                guard let snapshot = snapshots[venue.id], let placeID = snapshot.place.id else { throw RoutingFailure.missingVisitContext }
                                // TJ stop discovery needs an independent access coordinate. Google
                                // Place IDs remain attached only to the Google walking adapter.
                                var endpoint = try venue.endpoint(backend: transit && backend == .googlePlaceID ? .valhallaAccess : backend, mode: transit ? .walking : .automobile, now: .now)
                                endpoint.id = placeID; endpoints[placeID] = endpoint; points[placeID] = venue.displayPoint
                                if index > 0 {
                                    var visit = VisitContextRequest(placeID: placeID, day: ContextClock.label(departure))
                                    visit.identityConfirmed = true; visit.durationMinutes = 30; visit.startStepMinutes = 5
                                    stops.append(.init(snapshot: snapshot, request: visit))
                                }
                            }
                            let originID = try candidates.first.flatMap { snapshots[$0.id]?.place.id }.unwrap()
                            var input = ContextPlanRequest(originID: originID, returnID: originID, departure: departure, deadline: ContextClock.calendar.startOfDay(for: departure).addingTimeInterval(23 * 3600), stops: stops)
                            input.maxTravelCalls = 24; input.allVisitSlots = true; input.maximumTotalWaitingMinutes = 120
                            let memo = RoutingMemo(base: base, limit: 128)
                            activeMemo = memo
                            let adapter: any ContextTravelProvider
                            if transit {
                                let provenance = backend == .googlePlaceID ? "google_routes_walking" : backend == .valhallaAccess ? "valhalla_osm_walking" : "apple_maps_rest_walking"
                                let googleIDs = backend == .googlePlaceID ? Dictionary(uniqueKeysWithValues: endpoints.keys.map { ($0, $0) }) : [:]
                                adapter = try RoutingTransitAdapter(endpoints: endpoints, feed: BuswayFeed.network(), walking: .init(provider: memo, provenance: provenance, googlePlaceIDs: googleIDs), now: .now)
                            } else { adapter = RoutingTravelAdapter(endpoints: endpoints, provider: memo, mode: .automobile) }
                            let required = Set(stops.map { $0.request.placeID })
                            var priors: [RoutingPair: Double] = [:]
                            if policy == "finalists", backend == .googlePlaceID, !transit, let google {
                                let ids = [originID] + stops.map { $0.request.placeID }
                                let locations = ids.compactMap { endpoints[$0] }
                                let matrix = try await google.matrix(sources: locations, targets: locations, mode: .automobile, departure: departure)
                                for a in ids.indices { for b in ids.indices { if let value = matrix[a][b] { priors[.init(ids[a], ids[b])] = value } } }
                            }
                            let result: ContextItineraryResult
                            if policy == "baseline" { result = try await OptionalItineraryPlanner.plan(input, requiredIDs: required, provider: adapter, now: .now) }
                            else { result = try await FinalistRoutingPlanner.plan(input, required: required, provider: adapter, points: points, priors: priors, now: .now) }
                            var observation = RoutingFixtures.observation(id: id, backend: backend.rawValue, policy: policy, mode: transit ? "LIVE_WALKING_STATIC_GTFS" : "LIVE", seconds: RoutingFixtures.seconds(clock), result: result, required: required, input: input)
                            observation.calls = backend == .googlePlaceID ? budget.requests - requestsBefore : memo.calls
                            rows.append(observation)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            let failure = error as? RoutingFailure
                            let dispatched = backend == .googlePlaceID ? budget.requests - requestsBefore : activeMemo?.calls ?? 0
                            rows.append(.init(caseID: id, backend: backend.rawValue, policy: policy, evidenceMode: dispatched == 0 ? "LIVE_PREFLIGHT" : "LIVE", outcome: failure?.rawValue ?? "provider_or_context_failure", wallSeconds: RoutingFixtures.seconds(clock), calls: dispatched, visited: 0, requiredRetained: false, orderRetained: false, deadlineMet: false, arithmeticValid: true, accessStatus: "unverified", searchLimited: false))
                            if let failure, [.budgetExhausted, .authentication, .throttled].contains(failure) { continue backendLoop }
                        }
                    }
                }
            }
        }
        return rows
    }
    private static func row(_ id: String, backend: RouteBackend, mode: RouteMode, repetition: Int, probe: Bool, outcome: String, seconds: Double, calls: Int, access: String) -> RoutingObservation {
        .init(caseID: "\(id)-\(mode.rawValue)-r\(repetition)", backend: probe ? "valhalla_poi_probe" : backend.rawValue, policy: "fixed_leg", evidenceMode: probe ? "LOCAL_OSM_GRAPH" : calls == 0 ? "LIVE_PREFLIGHT" : "LIVE", outcome: outcome, wallSeconds: seconds, calls: calls, visited: 0, requiredRetained: true, orderRetained: true, deadlineMet: true, arithmeticValid: true, accessStatus: access, searchLimited: false)
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped { guard let self else { throw RoutingFailure.missingConfiguration }; return self }
}
