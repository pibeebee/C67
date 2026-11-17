import Foundation
import CryptoKit
import C67Domain

struct V41ItineraryPlanner: Sendable {
    let services: PocketPlanningServices
    let hours: @Sendable (String) async -> PlanningHoursLookup
    var quoteLimit = 72
    var candidateLimit = 500
    var synthetic = false
    var reserveRoute: @Sendable (Int) async throws -> Void = { _ in }

    func plan(_ job: PlanningJob, snapshots: [PlanningSemanticSnapshot] = [],
              retain: @Sendable (PlanningSemanticSnapshot) async throws -> Void = { _ in }) async throws -> PlanningResult {
        guard (1 ... 6).contains(job.input.places.count) else { throw PlanningError.failed("V4_UNSUPPORTED_INPUT") }
        let routes = V41RouteSession(input: job.input, services: services, limit: quoteLimit,
                                     candidateLimit: candidateLimit, initialCalls: job.scheduleAssessment?.routeCalls ?? 0, reserve: reserveRoute)
        var inputs = try PlanningDayWindow.v41Inputs(job.input, at: job.createdAt)
        var dates: [PlanningDateAssessment] = []
        var lastFailure: PlanningScheduleFailure?
        var best: PlanProposal?
        var modelCalls = 0
        var retained = snapshots
        var index = 0
        while index < inputs.count {
            try Task.checkCancellation()
            let input = inputs[index]
            index += 1
            do {
                try checkPinnedDate(input)
                var semantic: PlanningExperiencePlan?
                let key = try Self.semanticKey(input)
                let needsDuration = input.places.contains { $0.activitySession == nil && !($0.durationOverridden == true && $0.visitSeconds > 0) }
                let assistance = input.enginePreferences?.semanticAssistance ?? .whenNeeded
                if assistance != .disabled, input.enginePreferences?.usesLuna != false,
                   needsDuration || assistance == .requested {
                    if let snapshot = retained.first(where: { $0.contextKey == key }) { semantic = snapshot.plan }
                    else if input.enginePreferences?.allowsAIProcessing == true, let order = services.order {
                        var request = input
                        // Experience enrichment uses the existing server contract. The device runs v4.1.
                        request.enginePreferences?.orderingMethod = .hybridV4
                        let id = PocketPlanningRepository.identity("v4.1:\(job.id):\(key)")
                        var generated: PlanningExperiencePlan?
                        do {
                            modelCalls += 1
                            generated = try await order(request, id).validated(for: request)
                        } catch {
                            try Task.checkCancellation()
                            if needsDuration, error as? PlanningError == .unavailable { throw error }
                        }
                        if let generated {
                            let snapshot = PlanningSemanticSnapshot(contextKey: key, plan: generated)
                            try await retain(snapshot)
                            retained.append(snapshot)
                            semantic = generated
                        }
                    }
                }
                var proposal = try await schedule(input, semantic: semantic, routes: routes)
                if semantic == nil, assistance == .requested {
                    proposal.scheduleAssessment?.unresolved.append(.init(code: "semantic_unavailable"))
                    proposal.warnings.append("Luna suggestions are unavailable. Your supplied visit durations were used.")
                }
                dates.append(.init(date: input.startsAt, stopReason: proposal.scheduleAssessment?.stopReason ?? "scheduled",
                                   completeCandidates: proposal.scheduleAssessment?.completeCandidates ?? 0))
                if best == nil || proposalKey(proposal).lexicographicallyPrecedes(proposalKey(best!)) { best = proposal }
            } catch let failure as PlanningScheduleFailure {
                var failure = failure
                failure.assessment.routeCalls = await routes.calls
                lastFailure = failure
                dates.append(.init(date: input.startsAt, stopReason: failure.assessment.stopReason, completeCandidates: 0))
                if failure.code == "V4_WINDOW_TOO_SHORT", inputs.count == 1,
                   job.input.enginePreferences?.usesAutomaticTripDate == true,
                   job.input.enginePreferences?.tripTiming == nil,
                   job.input.enginePreferences?.scheduleSource != .manual,
                   PlanningDayWindow.isSameDay(input.startsAt, job.createdAt, timeZone: input.timeZone),
                   !input.places.contains(where: { $0.visitConfirmation != nil || $0.activitySession != nil || $0.preferredAfter != nil || $0.preferredBefore != nil }),
                   let tomorrow = PlanningDayWindow.tomorrow(after: job.createdAt, timeZone: input.timeZone) {
                    var next = input
                    next.startsAt = tomorrow.start
                    next.finishBy = tomorrow.end
                    inputs.append(next)
                }
            }
            if await routes.stopReason != nil { break }
        }
        if var best {
            best.scheduleAssessment?.dates = dates
            best.scheduleAssessment?.modelCalls = modelCalls
            best.scheduleAssessment?.routeCalls = await routes.calls
            if let reason = await routes.stopReason {
                best.scheduleAssessment?.stopReason = reason
                best.warnings.append(reason == "route_throttled" ?
                    "Apple Maps limited further checks. This itinerary uses completed route estimates." :
                    "The route-search limit was reached. Additional candidates or dates remain unchecked.")
            }
            if inputs.first.map({ !PlanningDayWindow.isSameDay($0.startsAt, best.input.startsAt, timeZone: best.input.timeZone) }) == true {
                best.rescheduledFromDate = inputs.first?.startsAt
            }
            return .init(proposal: best, candidates: [], warnings: best.warnings, synthetic: synthetic)
        }
        var failure = lastFailure ?? .init(code: "V41_NO_SCHEDULE", assessment: .init())
        failure.assessment.dates = dates
        failure.assessment.modelCalls = modelCalls
        failure.assessment.routeCalls = await routes.calls
        if let reason = await routes.stopReason {
            failure.assessment.stopReason = reason
            failure = .init(code: reason == "route_throttled" ? "V4_ROUTE_THROTTLED" : "V41_BUDGET_REACHED", assessment: failure.assessment)
        } else if failure.code == "V4_WINDOW_TOO_SHORT", inputs.count == 1,
                  !job.input.places.contains(where: { $0.activitySession != nil || $0.visitConfirmation != nil || $0.preferredAfter != nil || $0.preferredBefore != nil }),
                  PlanningDayWindow.isSameDay(inputs[0].startsAt, job.createdAt, timeZone: job.input.timeZone) {
            failure = .init(code: "V4_TODAY_TOO_SHORT", assessment: failure.assessment)
        }
        throw failure
    }

    func schedule(_ input: PlanningInput, semantic: PlanningExperiencePlan?, routes: V41RouteSession) async throws -> PlanProposal {
        try checkPinnedDate(input)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: input.timeZone)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let semantic = semantic.flatMap { value in
            value.candidateDate == dateFormatter.string(from: input.startsAt) && value.timeZone == input.timeZone ? value : nil
        }
        let earliest = Int(ceil(input.startsAt.timeIntervalSince1970 / 60))
        let deadline = Int(floor(input.finishBy.timeIntervalSince1970 / 60))
        var stops: [V4Stop] = []
        var modelTargets: [String: V4Target] = [:]
        var preflight = PlanningScheduleAssessment()
        for place in input.places {
            let suggestion = semantic?.stop(place.id)
            let duration: V4Duration?
            if let session = place.activitySession {
                let minutes = Int(ceil(session.endsAt.timeIntervalSince(session.startsAt) / 60))
                duration = .init(minimum: minutes, target: minutes, maximum: minutes, basis: "user", source: "traveller_session")
            } else if place.durationOverridden == true, place.visitSeconds > 0 {
                let minutes = Int(ceil(Double(place.visitSeconds) / 60))
                duration = .init(minimum: place.minimumAcceptedVisitSeconds.map { Int(ceil(Double($0) / 60)) } ?? minutes,
                                 target: minutes, maximum: minutes, basis: "user", source: "traveller")
            } else if let estimate = suggestion?.duration {
                duration = .init(minimum: estimate.minMinutes, target: estimate.suggestedSeconds / 60,
                                 maximum: estimate.maxMinutes, basis: "estimate", source: "luna_experience_estimate")
            } else {
                duration = nil
                preflight.unresolved.append(.init(code: "duration_unknown", placeID: place.id))
            }
            let access = await accessHours(place, input: input)
            var target: V4Target?
            if let session = place.activitySession {
                let start = Int(session.startsAt.timeIntervalSince1970 / 60)
                target = .init(earliest: start, latest: start, strength: "hard", origin: "user", source: "traveller_session")
            } else if let timing = place.visitTiming, place.preferredAfter != nil || place.preferredBefore != nil {
                target = .init(earliest: place.preferredAfter.map { Int(ceil($0.timeIntervalSince1970 / 60)) } ?? earliest,
                               latest: timing == .notBefore ? deadline : (place.preferredBefore.map { Int(floor($0.timeIntervalSince1970 / 60)) } ?? deadline),
                               strength: timing == .preferred ? "soft" : "hard", origin: "user", source: "traveller_visit_timing")
            }
            if target == nil, let raw = suggestion?.preferredDayPart, let part = PlanningDayPart(rawValue: raw),
               let zone = TimeZone(identifier: input.timeZone) {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                let midnight = Int(calendar.startOfDay(for: input.startsAt).timeIntervalSince1970 / 60)
                modelTargets[place.id.uuidString] = .init(earliest: midnight + part.minuteRange.lowerBound,
                                                          latest: midnight + part.minuteRange.upperBound - 1, strength: "soft", origin: "model", source: "luna_daypart_estimate")
            }
            stops.append(.init(id: place.id.uuidString, duration: duration, hours: access, target: target))
        }
        let wait = max(0, input.enginePreferences?.maximumWaitMinutes ?? 0)
        let departures = input.enginePreferences?.flexibleDeparture == true ? Array(stride(from: earliest, to: deadline, by: 30)) : [earliest]
        let trip = V4Trip(id: UUID().uuidString, origin: "origin", endpoint: "endpoint", stops: stops,
                          earliest_departure: earliest, return_deadline: deadline, departures: departures.isEmpty ? [earliest] : departures,
                          waiting: .init(per_stop: wait, total: wait), wait_choices: [0], first_id: input.firstPlaceID?.uuidString,
                          locked: input.preservesPlaceOrder, duration_policy: "target", objective: "compact",
                          last_id: input.enginePreferences?.lastPlaceID?.uuidString)
        let independent = V4Planner.evaluate(trip, .init(order: stops.map(\.id), departure: earliest, waits: stops.map { _ in 0 })) { _, _, _ in
            .init(minutes: nil, meters: nil, status: "not_requested")
        }
        preflight.conflicts = independent.conflicts.map { .init(code: $0.code, placeID: UUID(uuidString: $0.place), source: $0.source) }
        preflight.regularConflicts = independent.regular_conflicts.map { .init(code: $0.code, placeID: UUID(uuidString: $0.place), source: $0.source) }
        for left in stops.indices {
            for right in stops.indices where right > left {
                guard let a = stops[left].target, a.strength == "hard", let aDuration = stops[left].duration,
                      let b = stops[right].target, b.strength == "hard", let bDuration = stops[right].duration else { continue }
                if a.earliest + aDuration.minimum > b.latest, b.earliest + bDuration.minimum > a.latest {
                    for stop in [stops[left], stops[right]] {
                        preflight.conflicts.append(.init(code: "required_visits_overlap", placeID: UUID(uuidString: stop.id), source: "traveller_required_timing"))
                    }
                }
            }
        }
        preflight.unresolved += stops.filter { $0.hours.kind != "confirmed" }.map { .init(code: "date_access_unverified", placeID: UUID(uuidString: $0.id), source: $0.hours.source) }
        let visitMinutes = stops.compactMap(\.duration?.target).reduce(0, +)
        if earliest >= deadline || visitMinutes > deadline - earliest {
            preflight.conflicts.append(.init(code: "duration_exceeds_day"))
        }
        let earlyCode: String?
        if !preflight.conflicts.isEmpty || !preflight.regularConflicts.isEmpty {
            earlyCode = preflight.conflicts.contains { $0.code == "duration_exceeds_day" } ? "V4_WINDOW_TOO_SHORT" : "V41_ACCESS_CONFLICT"
        } else { earlyCode = preflight.unresolved.contains { $0.code == "duration_unknown" } ? "V4_DURATION_UNKNOWN" : nil }
        if let earlyCode {
            preflight.stopReason = "preflight_conflict"
            if earlyCode == "V4_WINDOW_TOO_SHORT" {
                preflight.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes)
            }
            throw PlanningScheduleFailure(code: earlyCode, assessment: preflight)
        }
        var result = try await V41Planner.search(trip, input: input, modelTargets: modelTargets, routes: routes)
        guard let selected = result.selected else {
            result.assessment.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes)
            let timeConflict = result.assessment.allCandidatesMissedDeadline
            throw PlanningScheduleFailure(code: timeConflict ? "V4_WINDOW_TOO_SHORT" : "V41_NO_SCHEDULE", assessment: result.assessment)
        }
        let scheduled = selected.visits.compactMap { visit -> ScheduledPlanningStop? in
            guard let place = input.places.first(where: { $0.id.uuidString == visit.id }), let start = visit.start,
                  let arrival = visit.arrival, let end = visit.end, let duration = visit.duration,
                  let travel = visit.quote.minutes, let meters = visit.quote.meters else { return nil }
            var stop = ScheduledPlanningStop(id: place.id, name: place.name, location: place.location,
                                             arrivalAt: Date(timeIntervalSince1970: Double(arrival * 60)), departureAt: Date(timeIntervalSince1970: Double(end * 60)),
                                             visitSeconds: duration * 60, travelSeconds: travel * 60, warnings: [])
            stop.visitStartsAt = Date(timeIntervalSince1970: Double(start * 60))
            stop.roadDistanceMeters = Double(meters)
            if place.durationOverridden != true, place.activitySession == nil { stop.warnings.append("Visit duration is a Luna estimate.") }
            if modelTargets[visit.id] != nil { stop.warnings.append("Preferred activity time is a Luna suggestion.") }
            return stop
        }
        guard scheduled.count == input.places.count else { throw PlanningError.invalidResponse }
        var proposal = PlanProposal(id: UUID(), input: input, stops: scheduled,
                                    finishesAt: selected.finish.map { Date(timeIntervalSince1970: Double($0 * 60)) }, feasible: true,
                                    explanation: "Hybrid v4.1 checked \(result.assessment.evaluatedCandidates) candidates with departure-specific travel estimates.",
                                    warnings: result.assessment.messages(in: input), evidence: [], synthetic: synthetic)
        if input.enginePreferences?.scheduleSource == .automatic || input.enginePreferences?.scheduleSource == .timingAnswer {
            proposal.input.enginePreferences?.scheduleSource = .resolved
        }
        if input.enginePreferences?.usesAutomaticTripDate == true { proposal.input.enginePreferences?.usesAutomaticTripDate = false }
        proposal.firstItinerary = true
        proposal.departureAt = Date(timeIntervalSince1970: Double(selected.spec.departure * 60))
        proposal.returnTravelSeconds = selected.return_quote?.minutes.map { $0 * 60 }
        proposal.experienceRouteCheckedAt = .now
        proposal.experiencePlan = semantic
        proposal.scheduleAssessment = result.assessment
        proposal.warnings.append("Regular hours may differ on the selected date. Search uses a finite departure grid and the earliest necessary waiting within your allowance.")
        return proposal
    }

    private func alternatives(_ input: PlanningInput, semantic: PlanningExperiencePlan?, routes: V41RouteSession) async throws -> [PlanningDurationAlternative] {
        guard input.places.allSatisfy({ $0.activitySession != nil || ($0.durationOverridden == true && $0.visitSeconds > 0) || semantic?.stop($0.id)?.duration != nil }) else { return [] }
        // Sensitivity candidates are evaluated once; their recursive alternatives are disabled by exact overrides.
        let choices = input.places.compactMap { place -> PlanningDurationAlternative? in
            guard place.activitySession == nil else { return nil }
            let estimate = semantic?.stop(place.id)?.duration
            let target = place.durationOverridden == true ? place.visitSeconds : (estimate?.suggestedSeconds ?? 0)
            let minimum = place.durationOverridden == true ? place.minimumAcceptedVisitSeconds : estimate.map { $0.minMinutes * 60 }
            guard let minimum, minimum > 0, minimum < target else { return nil }
            return .init(placeID: place.id, originalSeconds: target, proposedSeconds: minimum,
                         source: place.durationOverridden == true ? "traveller_accepted_minimum" : "luna_experience_estimate",
                         startsAt: input.startsAt, finishBy: input.finishBy)
        }.sorted { ($0.originalSeconds - $0.proposedSeconds) > ($1.originalSeconds - $1.proposedSeconds) }
        for choice in choices.prefix(2) {
            var shorter = input
            for index in shorter.places.indices {
                let place = shorter.places[index]
                shorter.places[index].visitSeconds = place.id == choice.placeID ? choice.proposedSeconds :
                    (place.durationOverridden == true ? place.visitSeconds : (semantic?.stop(place.id)?.duration?.suggestedSeconds ?? place.visitSeconds))
                shorter.places[index].durationOverridden = true
                shorter.places[index].minimumAcceptedVisitSeconds = nil
            }
            if (try? await schedule(shorter, semantic: semantic, routes: routes)) != nil { return [choice] }
            if await routes.stopReason != nil { break }
        }
        return []
    }

    private func checkPinnedDate(_ input: PlanningInput) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZone)!
        var assessment = PlanningScheduleAssessment()
        let dayStart = calendar.startOfDay(for: input.startsAt)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        for place in input.places {
            let targets = [place.activitySession?.startsAt, place.preferredAfter, place.preferredBefore].compactMap { $0 }
            var outside = targets.contains { !calendar.isDate($0, inSameDayAs: input.startsAt) }
            if let access = place.visitConfirmation, access.closesAt <= dayStart || access.opensAt >= dayEnd { outside = true }
            if outside {
                assessment.conflicts.append(.init(code: "session_outside_date", placeID: place.id, source: "traveller"))
            }
        }
        if !assessment.conflicts.isEmpty {
            assessment.stopReason = "date_conflict"
            throw PlanningScheduleFailure(code: "V41_DATE_CONFLICT", assessment: assessment)
        }
    }

    private func accessHours(_ place: PlanningPlace, input: PlanningInput) async -> V4Hours {
        if let value = place.visitConfirmation, value.publicAccessConfirmed {
            return .init(kind: "confirmed", windows: [.init(opens: Int(ceil(value.opensAt.timeIntervalSince1970 / 60)),
                                                            closes: Int(floor(value.closesAt.timeIntervalSince1970 / 60)), last_entry: value.lastEntryAt.map { Int(floor($0.timeIntervalSince1970 / 60)) })], source: "traveller_confirmation")
        }
        guard let source = place.sourceID, source.hasPrefix("apple:") else { return .init(kind: "unknown", windows: [], source: nil) }
        let lookup = await hours(String(source.dropFirst(6)))
        guard lookup.status == "available", let regular = lookup.hours,
              let zone = TimeZone(identifier: regular.timezone), regular.weekly.count == 7,
              Set(regular.weekly.map(\.weekday)) == Set(1 ... 7) else {
            return .init(kind: lookup.status == "unavailable" ? "unknown" : "error", windows: [], source: lookup.status)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: input.startsAt))!
        var windows: [V4Window] = []
        while day <= input.finishBy {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next.timeIntervalSince(day) == 86400,
                  let record = regular.weekly.first(where: { $0.weekday == calendar.component(.weekday, from: day) }) else {
                return .init(kind: "error", windows: [], source: "hours_calendar_unresolved")
            }
            for interval in record.intervals {
                let a = interval.startSeconds, b = interval.endSeconds
                guard (0 ..< 86400).contains(a), (0 ... 86400).contains(b), a != b else { return .init(kind: "error", windows: [], source: "invalid_hours") }
                if b <= a, let following = calendar.date(byAdding: .day, value: 1, to: next), following.timeIntervalSince(next) != 86400 {
                    return .init(kind: "error", windows: [], source: "hours_calendar_unresolved")
                }
                let end = (b <= a ? next : day).addingTimeInterval(Double(b))
                windows.append(.init(opens: Int(day.addingTimeInterval(Double(a)).timeIntervalSince1970 / 60),
                                     closes: Int(end.timeIntervalSince1970 / 60), last_entry: nil))
            }
            day = next
        }
        var merged: [V4Window] = []
        for window in windows.sorted(by: { $0.opens < $1.opens }) {
            if let last = merged.last, window.opens <= last.closes { merged[merged.count - 1].closes = max(last.closes, window.closes) }
            else { merged.append(window) }
        }
        let relevant = merged.filter { $0.closes > Int(input.startsAt.timeIntervalSince1970 / 60) && $0.opens < Int(input.finishBy.timeIntervalSince1970 / 60) }
        return .init(kind: "regular", windows: relevant, source: "apple_regular_hours")
    }

    private static func semanticKey(_ input: PlanningInput) throws -> String {
        struct Context: Encodable {
            var places: [PlanningPlace]
            var preferences: String
            var date: String
            var timeZone: String
            var mainSpotID: UUID?
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: input.timeZone)
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let places = input.places.sorted { $0.id.uuidString < $1.id.uuidString }.map { value in
            var place = value
            place.visitSeconds = 0; place.durationOverridden = nil; place.minimumAcceptedVisitSeconds = nil
            place.preferredAfter = nil; place.preferredBefore = nil; place.visitTiming = nil
            place.visitConfirmation = nil; place.activitySession = nil
            return place
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Context(places: places, preferences: input.preferences, date: formatter.string(from: input.startsAt),
                                              timeZone: input.timeZone, mainSpotID: input.enginePreferences?.mainSpotID))
        return SHA256.hash(data: Data("v4.1-semantic-v1:".utf8) + data).map { String(format: "%02x", $0) }.joined()
    }

    private func proposalKey(_ proposal: PlanProposal) -> [Int] {
        [proposal.scheduleAssessment?.preferredPeriodOutsideMinutes ?? 0,
         Int((proposal.finishesAt ?? proposal.input.finishBy).timeIntervalSince(proposal.departureAt ?? proposal.input.startsAt) / 60)]
    }
}
