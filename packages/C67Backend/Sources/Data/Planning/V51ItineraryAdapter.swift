import C67Domain
import C67PlannerV5
import Foundation
import PocketEngine

extension V41ItineraryPlanner {
    func scheduleV51(_ input: PlanningInput, semantic: PlanningExperiencePlan?, routes: V41RouteSession,
                     preparedHours: [String: PlanningHoursLookup],
                     remainingVisit: (id: UUID, seconds: Int)?, requestID: UUID?) async throws -> PlanProposal {
        guard input.startsAt < input.finishBy else { throw PlanningError.invalidInput }
        await PocketPlanningActivity.show(.openingHours)
        let forecastStarted = ContinuousClock.now
        let forecasts = try await forecastsV51(input, excluding: remainingVisit?.id)
        if let requestID { Self.logPhase("schedule_forecast", since: forecastStarted, requestID: requestID) }
        var engineInput = input
        var contexts: [UUID: PlannerV5VisitContext] = [:]
        var regularAccess: Set<UUID> = []
        var assessment = PlanningScheduleAssessment()
        for index in input.places.indices {
            let place = input.places[index]
            if let remainingVisit, remainingVisit.id == place.id {
                engineInput.places[index].activitySession = nil
                engineInput.places[index].visitConfirmation = nil
                engineInput.places[index].preferredAfter = nil
                engineInput.places[index].preferredBefore = nil
                engineInput.places[index].visitTiming = nil
                engineInput.places[index].durationOverridden = false
                let minutes = (remainingVisit.seconds + 59) / 60
                contexts[place.id] = .init(duration: .init(minutes: minutes ... minutes, target: minutes,
                                                           source: .observed("active_visit")))
                continue
            }
            let suggestion = semantic?.stop(place.id)
            var context = PlannerV5VisitContext(activity: suggestion?.activity.suggestion,
                                                activitySource: suggestion.map { .suggestion($0.activity.basis) })
            if let estimate = suggestion?.duration, !place.hasExplicitVisitDuration {
                let minutes = estimate.suggestedSeconds / 60
                context.duration = .init(minutes: minutes ... minutes, target: minutes, source: .suggestion(estimate.basis))
            } else if !place.hasExplicitVisitDuration {
                let seconds = place.visitSeconds > 0 ? place.visitSeconds : PlanProposal.defaultExperienceVisitSeconds
                let extra = input.enginePreferences?.mainSpotID == place.id ? 15 : 0
                let minutes = min(1440, (seconds + 59) / 60 + extra)
                context.duration = .init(minutes: minutes ... minutes, target: minutes, source: .localEstimate)
            }
            if place.visitConfirmation?.publicAccessConfirmed != true {
                let hours = await accessHours(place, input: input, preparedHours: preparedHours)
                if hours.kind == "regular" {
                    regularAccess.insert(place.id)
                    context.access = .init(windows: hours.windows.filter { $0.opens < $0.closes }.map {
                        .init(.init(start: Self.dateV51($0.opens), end: Self.dateV51($0.closes)),
                              lastEntry: $0.last_entry.map(Self.dateV51))
                    }, source: .venue("apple_regular_hours"))
                }
                assessment.unresolved.append(.init(code: "date_access_unverified", placeID: place.id, source: hours.source))
            }
            switch place.visitExposure {
            case .indoor:
                context.exposure = .indoor
                context.exposureSource = .traveller
            case .outdoor, .directSun, .sheltered:
                context.exposure = .outdoor
                context.exposureSource = .traveller
                if place.visitExposure == .directSun || place.visitExposure == .sheltered {
                    context.sunExposure = place.visitExposure == .directSun ? .direct : .sheltered
                    context.sunExposureSource = .traveller
                }
                context.outdoorWeather = forecasts[place.id]?.series ?? []
                context.rain = forecasts[place.id]?.rain ?? []
            default: break
            }
            contexts[place.id] = context
        }
        await PocketPlanningActivity.show(.travelTimes)
        await routes.startSearch()
        let planner = PlannerV51 { from, to, date, _ in
            let quote = try await routes.quote(from, to, Int(date.timeIntervalSince1970 / 60))
            guard let minutes = quote.minutes else { return nil }
            return .init(seconds: minutes * 60, meters: quote.meters)
        }
        let searchStarted = ContinuousClock.now
        let beforeETA = await routes.providerDuration
        let result = try await planner.plan(.init(trip: engineInput, visits: contexts,
                                                  extraTravelMinutes: input.enginePreferences?.extraTravelMinutes ?? 0,
                                                  checkInBufferMinutes: input.enginePreferences?.checkInBufferMinutes))
        if let requestID {
            let etaTime = await routes.providerDuration - beforeETA
            Self.logPhase("schedule_eta", since: .now - etaTime, requestID: requestID)
            Self.logPhase("schedule_evaluation", since: searchStarted + etaTime, requestID: requestID)
        }
        try Task.checkCancellation()
        try await routes.checkReservation()
        assessment.routeCalls = await routes.calls
        assessment.evaluatedCandidates = result.evaluatedCandidates
        assessment.stopReason = await routes.stopReason ?? result.limit.map { String(describing: $0) } ?? "domain_exhausted"
        guard let schedule = result.schedule else {
            for issue in result.issues {
                switch issue {
                case .access(let id):
                    let row = PlanningScheduleIssue(code: "visit_outside_hours_or_entry", placeID: id)
                    if regularAccess.contains(id) { assessment.regularConflicts.append(row) }
                    else { assessment.conflicts.append(row) }
                case .visitTime(let id): assessment.conflicts.append(.init(code: "required_target_missed", placeID: id))
                case .checkIn(let id): assessment.conflicts.append(.init(code: "session_arrival_missed", placeID: id))
                case .waiting(let id): assessment.conflicts.append(.init(code: "total_wait_exceeded", placeID: id))
                case .deadline: assessment.conflicts.append(.init(code: "return_deadline_exceeded"))
                case .etaUnavailable(_, let id): assessment.unresolved.append(.init(code: "eta:route_unavailable", placeID: id))
                }
            }
            if result.status == .incomplete {
                // Conflicts found on individual candidates do not prove that the search domain is infeasible.
                assessment.conflicts.removeAll()
                assessment.regularConflicts.removeAll()
                let bounded = result.limit == .routeQuotes || result.limit == .candidates
                    || assessment.stopReason.hasSuffix("budget_exhausted")
                let code = assessment.stopReason == "route_throttled" ? "PROVIDER_RATE_LIMITED"
                    : (bounded ? "V41_BUDGET_REACHED" : "V41_NO_SCHEDULE")
                throw PlanningScheduleFailure(code: code, assessment: assessment)
            }
            let deadlineOnly = !assessment.conflicts.isEmpty &&
                assessment.conflicts.allSatisfy { $0.code == "return_deadline_exceeded" } && assessment.regularConflicts.isEmpty
            assessment.allCandidatesMissedDeadline = deadlineOnly
            let access = !assessment.regularConflicts.isEmpty || assessment.conflicts.contains { $0.code == "visit_outside_hours_or_entry" }
            let code = deadlineOnly ? "V4_WINDOW_TOO_SHORT" : (access ? "V41_ACCESS_CONFLICT" : "V51_SCHEDULE_CONFLICT")
            throw PlanningScheduleFailure(code: code, assessment: assessment)
        }
        assessment.completeCandidates = result.completeCandidates
        assessment.preferredPeriodOutsideMinutes = schedule.preferredTimeDeviation
        assessment.remainingMinutes = Int(input.finishBy.timeIntervalSince(schedule.finishesAt) / 60)
        let stops = zip(schedule.visits, schedule.legs).map { visit, leg in
            let place = input.places.first { $0.id == visit.placeID }!
            let warnings = visit.duration.source == .localEstimate ? ["Visit duration is estimated by Travelants."] : []
            var stop = ScheduledPlanningStop(id: place.id, name: place.name, location: place.location,
                                             arrivalAt: visit.arrivesAt, departureAt: visit.endsAt,
                                             visitSeconds: visit.duration.target * 60, travelSeconds: leg.route.seconds, warnings: warnings)
            stop.visitStartsAt = visit.startsAt
            stop.roadDistanceMeters = leg.route.meters.map(Double.init)
            return stop
        }
        var seen: Set<String> = []
        let evidence = input.places.flatMap { forecasts[$0.id]?.evidence ?? [] }.filter { seen.insert($0.id).inserted }
        var warnings = assessment.messages(in: input)
        if result.limit != nil { warnings.append("Travelants selected from the schedules it could verify.") }
        var proposal = PlanProposal(id: UUID(), input: input, stops: stops, finishesAt: schedule.finishesAt, feasible: true,
                                    explanation: result.reason, warnings: warnings, evidence: evidence, synthetic: synthetic)
        proposal.departureAt = schedule.departsAt
        proposal.returnTravelSeconds = input.planningEndpoint == nil ? nil : schedule.legs.last?.route.seconds
        proposal.experienceRouteCheckedAt = .now
        proposal.experiencePlan = semantic
        proposal.firstItinerary = true
        proposal.scheduleAssessment = assessment
        proposal.scheduleDecision = decisionV51(result, schedule: schedule, places: input.places)
        if input.enginePreferences?.scheduleSource == .automatic || input.enginePreferences?.scheduleSource == .timingAnswer {
            proposal.input.enginePreferences?.scheduleSource = .resolved
        }
        if input.enginePreferences?.usesAutomaticTripDate == true { proposal.input.enginePreferences?.usesAutomaticTripDate = false }
        return proposal
    }

    private static func dateV51(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }

    private func forecastsV51(_ input: PlanningInput, excluding: UUID?) async throws -> [UUID: PocketScheduleForecast] {
        guard let forecast = services.scheduleForecast else { return [:] }
        let outdoor = input.places.filter {
            $0.id != excluding && [.outdoor, .sheltered, .directSun].contains($0.visitExposure)
        }
        var output: [UUID: PocketScheduleForecast] = [:]
        let coordinates = Dictionary(grouping: outdoor) { Coordinate(latitude: $0.location.latitude, longitude: $0.location.longitude) }
        for places in coordinates.values.sorted(by: { $0[0].id.uuidString < $1[0].id.uuidString }) {
            do {
                let direct = places.contains { $0.visitExposure == .directSun }
                let reading = try await forecast(places[0].location, input.startsAt, input.finishBy, direct)
                for place in places { output[place.id] = reading }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
            }
        }
        return output
    }

    private func decisionV51(_ result: PlannerV5Result, schedule: PlannerV5Schedule,
                             places: [PlanningPlace]) -> PlanningScheduleDecision {
        let sessions = schedule.checkIns.map {
            PlanningScheduleDecision.CheckIn(id: $0.placeID, buffer: $0.bufferMinutes,
                                             target: $0.targetMinutes, shortfall: $0.shortfallMinutes)
        }
        let outdoor = schedule.outdoorVisits.map { visit in
            PlanningScheduleDecision.Outdoor(id: visit.placeID, interval: visit.interval, readings: visit.readings.map {
                .init(id: $0.kind.labelV51, value: $0.average, source: $0.source)
            })
        }
        var alternative: [String] = []
        if let other = result.alternative, let comparison = result.alternativeComparison {
            let names = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0.name) })
            alternative.append(other.visits.compactMap { names[$0.placeID] }.joined(separator: " → "))
            let delta = comparison.drivingMinutesDelta
            if delta != 0 { alternative.append("\(abs(delta)) min \(delta > 0 ? "more" : "less") travel") }
            for checkIn in other.checkIns where schedule.checkIns.first(where: { $0.placeID == checkIn.placeID })?.bufferMinutes != checkIn.bufferMinutes {
                alternative.append("\(names[checkIn.placeID] ?? "Visit") · \(checkIn.bufferMinutes.formatted()) min check-in buffer")
            }
            for change in comparison.weather {
                guard let delta = change.scoreDelta, abs(delta) > 1e-8 else { continue }
                let value = delta.formatted(.number.precision(.fractionLength(0 ... 1)).sign(strategy: .always()))
                alternative.append("\(names[change.placeID] ?? "Visit") · \(change.kind.labelV51) \(value)")
            }
        }
        return .init(checkIns: sessions, outdoor: outdoor, extraTravel: result.comparisonWithFastest?.drivingMinutesDelta ?? 0,
                     alternative: alternative)
    }
}

private extension PlannerV51WeatherKind {
    var labelV51: String {
        switch self {
        case .apparentTemperature: "Feels like (°C)"
        case .directIrradiance: "Direct sunlight (W/m²)"
        case .uvIndex: "UV index"
        }
    }
}
