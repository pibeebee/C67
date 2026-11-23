import Foundation
import OSLog
import CryptoKit
import C67Domain

struct V41ItineraryPlanner: Sendable {
    let services: PocketPlanningServices
    let hours: @Sendable (String) async -> PlanningHoursLookup
    var quoteLimit = 72
    var candidateLimit = 500
    var synthetic = false
    var reserveRoute: @Sendable (Int) async throws -> Void = { _ in }
    private static let logger = Logger(subsystem: "io.pibeebee.c67", category: "PlanningTiming")
    private static let localDurationSource = "local_visit_estimate"

    func plan(_ job: PlanningJob, snapshots: [PlanningSemanticSnapshot] = [],
              retain: @Sendable (PlanningSemanticSnapshot) async throws -> Void = { _ in },
              retainBatch: @Sendable ([PlanningSemanticSnapshot]) async throws -> Void = { _ in }) async throws -> PlanningResult {
        guard (1 ... 6).contains(job.input.places.count) else { throw PlanningError.failed("V4_UNSUPPORTED_INPUT") }
        let routes = V41RouteSession(input: job.input, services: services, limit: quoteLimit,
                                     candidateLimit: candidateLimit, initialCalls: job.scheduleAssessment?.routeCalls ?? 0, reserve: reserveRoute)
        var inputs = try PlanningDayWindow.v41Inputs(job.input, at: job.createdAt)
        let rollover = inputs.count == 1 ? rolloverInput(job, current: inputs[0]) : nil
        let canEstimateDuration = job.input.enginePreferences?.automaticFirstPlan == true
        let method = job.input.enginePreferences?.orderingMethod ?? .hybridV41
        let v42 = method.replacesLegacyV42
        let onDevice = method == .hybridV42FoundationModels
        let experience = onDevice ? services.foundationExperience : services.experience
        let requestID = job.command?.requestID ?? job.id
        let started = ContinuousClock.now
        let usesBatchHours = method == .hybridV52 && services.batchHours != nil
        async let prefetchedHours = v42 ? prepareHours(for: job.input.places, requestID: requestID, batch: usesBatchHours) : [:]
        var lookupBySource: [String: PlanningHoursLookup]?
        var comparedDates = false
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
            var semantic: PlanningExperiencePlan?
            var preparedHours: [String: PlanningHoursLookup] = [:]
            do {
                try checkPinnedDate(input)
                let key = try Self.semanticKey(input, method: method)
                let needsDuration = input.places.contains { !$0.hasExplicitVisitDuration }
                let assistance = input.enginePreferences?.semanticAssistance ?? .whenNeeded
                if assistance != .disabled, onDevice || input.enginePreferences?.usesLuna != false,
                   needsDuration || assistance == .requested {
                    if let snapshot = retained.first(where: { $0.contextKey == key }) { semantic = snapshot.plan }
                    else if input.enginePreferences?.allowsAIProcessing == true, v42, let experience,
                            !(index > 1 && rollover != nil && comparedDates) {
                        var candidates = [input]
                        if !comparedDates {
                            let remaining = Array(inputs.dropFirst(index)) + (inputs.count == 1 ? rollover.map { [$0] } ?? [] : [])
                            for future in remaining {
                                guard (try? checkPinnedDate(future)) != nil else { continue }
                                let key = try Self.semanticKey(future, method: method)
                                if !retained.contains(where: { $0.contextKey == key }) {
                                    candidates.append(future)
                                }
                            }
                        }
                        comparedDates = true
                        if onDevice { await PocketPlanningActivity.show(.onDeviceAdvice) }
                        var generated: [PlanningSemanticSnapshot] = []
                        do {
                            modelCalls += 1
                            generated = try await compactExperience(candidates, job: job, requestID: requestID, method: method, experience: experience)
                        } catch {
                            try Task.checkCancellation()
                            if !canEstimateDuration, candidates.count > 1, Self.shouldTryDatesSeparately(error) {
                                do {
                                    modelCalls += 1
                                    generated = try await compactExperience([input], job: job, requestID: requestID, method: method, experience: experience)
                                } catch {
                                    try Task.checkCancellation()
                                    if needsDuration, !Self.shouldTryDatesSeparately(error) { throw error }
                                }
                            } else if !canEstimateDuration, needsDuration, !Self.shouldTryDatesSeparately(error) { throw error }
                        }
                        if let selected = generated.first {
                            try await retainBatch(generated)
                            retained.append(contentsOf: generated)
                            semantic = selected.plan
                        }
                    } else if onDevice, experience == nil, needsDuration, !canEstimateDuration,
                              input.enginePreferences?.allowsAIProcessing == true {
                        throw PlanningError.failed("FOUNDATION_MODELS_UNAVAILABLE")
                    } else if !v42, input.enginePreferences?.allowsAIProcessing == true, let order = services.order,
                              !(canEstimateDuration && index > 1 && rollover != nil) {
                        var request = input
                        // Experience enrichment uses the existing server contract. The device runs v4.1.
                        request.enginePreferences?.orderingMethod = .hybridV4
                        let id = PocketPlanningRepository.identity("v4.1:\(job.id):\(key)")
                        var generated: PlanningExperiencePlan?
                        do {
                            modelCalls += 1
                            let started = ContinuousClock.now
                            defer { Self.logPhase("luna_round_trip", since: started, requestID: requestID, modelRequestID: id) }
                            generated = try await order(request, id).validated(for: request)
                        } catch {
                            try Task.checkCancellation()
                            if !canEstimateDuration, needsDuration, let cause = error as? PlanningError,
                               [.unavailable, .timedOut, .rateLimited].contains(cause) { throw error }
                        }
                        if let generated {
                            let snapshot = PlanningSemanticSnapshot(contextKey: key, plan: generated)
                            try await retain(snapshot)
                            retained.append(snapshot)
                            semantic = generated
                        }
                    }
                }
                if lookupBySource == nil {
                    if v42 { await PocketPlanningActivity.show(.openingHours) }
                    lookupBySource = try await prefetchedHours
                }
                try Task.checkCancellation()
                let prefetched = lookupBySource ?? [:]
                // A failed early lookup can recover by the time the route is ready.
                preparedHours = usesBatchHours ? prefetched : prefetched.filter { $0.value.status != "temporary_error" }
                lookupBySource = usesBatchHours ? preparedHours : preparedHours.filter { ["available", "unavailable"].contains($0.value.status) }
                var proposal = try await schedule(input, semantic: semantic, routes: routes, preparedHours: preparedHours, requestID: requestID, includesAlternatives: rollover == nil)
                if semantic == nil, assistance == .requested {
                    proposal.scheduleAssessment?.unresolved.append(.init(code: "semantic_unavailable"))
                    proposal.warnings.append(onDevice ?
                        "Foundation Models suggestions are unavailable. The itinerary uses the visit durations shown." :
                        "Luna suggestions are unavailable. The itinerary uses the visit durations shown.")
                }
                dates.append(.init(date: input.startsAt, stopReason: proposal.scheduleAssessment?.stopReason ?? "scheduled",
                                   completeCandidates: proposal.scheduleAssessment?.completeCandidates ?? 0))
                if best == nil || proposalKey(proposal).lexicographicallyPrecedes(proposalKey(best!)) { best = proposal }
            } catch let failure as PlanningScheduleFailure {
                var failure = failure
                failure.assessment.routeCalls = await routes.calls
                dates.append(.init(date: input.startsAt, stopReason: failure.assessment.stopReason, completeCandidates: 0))
                let dateLimited = failure.code == "V4_WINDOW_TOO_SHORT" ||
                    (failure.code == "V41_ACCESS_CONFLICT" && failure.assessment.conflicts.allSatisfy { $0.code == "return_deadline_exceeded" } &&
                        !failure.assessment.regularConflicts.isEmpty)
                if dateLimited, inputs.count == 1, let rollover, await routes.stopReason == nil {
                    inputs.append(rollover)
                } else if rollover != nil, index == inputs.count, best == nil,
                          ["V4_WINDOW_TOO_SHORT", "V41_NO_SCHEDULE"].contains(failure.code),
                          await routes.stopReason == nil {
                    failure.assessment.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes,
                                                                                     preparedHours: preparedHours)
                }
                lastFailure = failure
            } catch let failure as PlanningError where best != nil && Self.canReturnPartialComparison(failure) {
                dates.append(.init(date: input.startsAt, stopReason: "provider_unverified", completeCandidates: 0))
            }
            if await routes.stopReason != nil { break }
        }
        Self.logPhase("device_planning", since: started, requestID: requestID)
        let routeCalls = await routes.calls
        let mapTime = await routes.providerDuration
        Self.logger.info("planning_counts request_id=\(requestID.uuidString.lowercased(), privacy: .public) method=\(method.rawValue, privacy: .public) model_attempts=\(modelCalls) route_calls=\(routeCalls) mapkit_elapsed=\(String(describing: mapTime), privacy: .public)")
        if var best {
            best.scheduleAssessment?.dates = dates
            if dates.contains(where: { $0.stopReason == "provider_unverified" }) {
                best.warnings.append("Some dates could not be checked. This itinerary was validated for the date shown.")
            }
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

    private func rolloverInput(_ job: PlanningJob, current: PlanningInput) -> PlanningInput? {
        let options = job.input.enginePreferences
        let automatic = options?.usesAutomaticTripDate == true && options?.tripTiming == nil
        let wantsNow = options?.scheduleSource == .timingAnswer && options?.tripTiming == .now
        guard job.purpose == .firstItinerary, automatic || wantsNow,
              options?.scheduleSource != .manual, options?.scheduleSource != .resolved,
              PlanningDayWindow.isSameDay(current.startsAt, job.createdAt, timeZone: current.timeZone),
              !current.places.contains(where: { $0.visitConfirmation != nil || $0.activitySession != nil || $0.preferredAfter != nil || $0.preferredBefore != nil }),
              let tomorrow = PlanningDayWindow.tomorrow(after: job.createdAt, timeZone: current.timeZone) else { return nil }
        var input = current
        input.startsAt = tomorrow.start
        input.finishBy = tomorrow.end
        return input
    }

    private func compactExperience(_ inputs: [PlanningInput], job: PlanningJob, requestID: UUID,
                                   method: PlanningOrderingMethod,
                                   experience: @Sendable ([PlanningInput], UUID) async throws -> [PlanningExperiencePlan]) async throws -> [PlanningSemanticSnapshot] {
        let keys = try inputs.map { try Self.semanticKey($0, method: method) }
        let id = PocketPlanningRepository.identity("v4.2:\(job.id):\(keys.joined(separator: ":"))")
        let started = ContinuousClock.now
        let phase = method == .hybridV42FoundationModels ? "foundation_models_inference" : "luna_round_trip"
        defer { Self.logPhase(phase, since: started, requestID: requestID, modelRequestID: id) }
        let providerMethod: PlanningOrderingMethod = method.usesV5Scheduler ? .hybridV42 : method
        let providerInputs = inputs.map { input in
            var input = input
            input.enginePreferences?.orderingMethod = providerMethod
            return input
        }
        let plans = try await experience(providerInputs, id)
        guard plans.count == inputs.count else { throw PlanningError.invalidResponse }
        return try zip(zip(keys, providerInputs), plans).map { context, plan in
            let (key, input) = context
            try PocketOrderCodec.validateMethod(plan.orderingMethod, expected: providerMethod)
            return .init(contextKey: key, plan: try plan.validated(for: input))
        }
    }

    private static func canReturnPartialComparison(_ error: PlanningError) -> Bool {
        switch error {
        case .unavailable, .timedOut, .rateLimited, .invalidResponse, .failed("ORDER_GENERATION_FAILED"): true
        default: false
        }
    }

    private static func shouldTryDatesSeparately(_ error: any Error) -> Bool {
        if error is DecodingError { return true }
        guard let error = error as? PlanningError else { return false }
        return error == .invalidResponse || error == .failed("ORDER_GENERATION_FAILED")
    }

    func prepareHours(for places: [PlanningPlace], requestID: UUID? = nil, batch: Bool) async throws -> [String: PlanningHoursLookup] {
        let started = ContinuousClock.now
        let ids = Set(places.compactMap { place -> String? in
            guard place.visitConfirmation?.publicAccessConfirmed != true,
                  let source = place.sourceID, source.hasPrefix("apple:") else { return nil }
            let id = String(source.dropFirst(6))
            return id.range(of: "^I[0-9A-Fa-f]{1,63}$", options: .regularExpression) == nil ? nil : id
        }).sorted()
        guard !ids.isEmpty else { return [:] }
        defer { if let requestID { Self.logPhase("hours_prefetch", since: started, requestID: requestID) } }
        if batch, let lookup = services.batchHours, let results = try await lookup(ids) { return results }
        try Task.checkCancellation()
        let results = await withTaskGroup(of: (String, PlanningHoursLookup).self) { group in
            var remaining = ids.makeIterator()
            for id in ids.prefix(2) {
                group.addTask { (id, await hours(id)) }
                _ = remaining.next()
            }
            var output: [String: PlanningHoursLookup] = [:]
            for await (id, result) in group {
                output[id] = result
                if !Task.isCancelled, let next = remaining.next() { group.addTask { (next, await hours(next)) } }
            }
            return output
        }
        try Task.checkCancellation()
        return results
    }

    static func logPhase(_ phase: String, since started: ContinuousClock.Instant, requestID: UUID, modelRequestID: UUID? = nil) {
        logger.info("planning_phase request_id=\(requestID.uuidString.lowercased(), privacy: .public) order_id=\(modelRequestID?.uuidString.lowercased() ?? "-", privacy: .public) phase=\(phase, privacy: .public) elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
    }

    func schedule(_ input: PlanningInput, semantic: PlanningExperiencePlan?, routes: V41RouteSession,
                  preparedHours: [String: PlanningHoursLookup] = [:], requestID: UUID? = nil,
                  remainingVisit: (id: UUID, seconds: Int)? = nil, includesAlternatives: Bool = true) async throws -> PlanProposal {
        var datedInput = input
        datedInput.places.removeAll { $0.id == remainingVisit?.id }
        try checkPinnedDate(datedInput)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: input.timeZone)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let semantic = semantic.flatMap { value in
            value.candidateDate == dateFormatter.string(from: input.startsAt) && value.timeZone == input.timeZone ? value : nil
        }
        if input.enginePreferences?.orderingMethod?.usesV5Scheduler == true {
            do {
                return try await scheduleV51(input, semantic: semantic, routes: routes, preparedHours: preparedHours,
                                             remainingVisit: remainingVisit, requestID: requestID)
            } catch var failure as PlanningScheduleFailure {
                if includesAlternatives, remainingVisit == nil,
                   ["V4_WINDOW_TOO_SHORT", "V41_ACCESS_CONFLICT", "V51_SCHEDULE_CONFLICT"].contains(failure.code),
                   await routes.stopReason == nil {
                    failure.assessment.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes,
                                                                                     preparedHours: preparedHours)
                }
                throw failure
            }
        }
        let onDevice = input.enginePreferences?.orderingMethod == .hybridV42FoundationModels
        let durationSource = onDevice ? "foundation_models_experience_estimate" : "luna_experience_estimate"
        let daypartSource = onDevice ? "foundation_models_daypart_estimate" : "luna_daypart_estimate"
        let earliest = Int(ceil(input.startsAt.timeIntervalSince1970 / 60))
        let deadline = Int(floor(input.finishBy.timeIntervalSince1970 / 60))
        var stops: [V4Stop] = []
        var modelTargets: [String: V4Target] = [:]
        var preflight = PlanningScheduleAssessment()
        await PocketPlanningActivity.show(.openingHours)
        let accessStarted = ContinuousClock.now
        for place in input.places {
            let suggestion = semantic?.stop(place.id)
            let duration: V4Duration?
            if let remainingVisit, remainingVisit.id == place.id {
                let minutes = Int(ceil(Double(remainingVisit.seconds) / 60))
                duration = .init(minimum: minutes, target: minutes, maximum: minutes, basis: "user", source: "active_visit")
            } else if let session = place.activitySession {
                let minutes = Int(ceil(session.endsAt.timeIntervalSince(session.startsAt) / 60))
                duration = .init(minimum: minutes, target: minutes, maximum: minutes, basis: "user", source: "traveller_session")
            } else if place.durationOverridden == true, place.visitSeconds > 0 {
                let minutes = Int(ceil(Double(place.visitSeconds) / 60))
                duration = .init(minimum: place.minimumAcceptedVisitSeconds.map { Int(ceil(Double($0) / 60)) } ?? minutes,
                                 target: minutes, maximum: minutes, basis: "user", source: "traveller")
            } else if let estimate = suggestion?.duration {
                duration = .init(minimum: estimate.minMinutes, target: estimate.suggestedSeconds / 60,
                                 maximum: estimate.maxMinutes, basis: "estimate", source: durationSource)
            } else if input.enginePreferences?.automaticFirstPlan == true {
                let seconds = place.visitSeconds > 0 ? min(place.visitSeconds, 86_400) : PlanProposal.defaultExperienceVisitSeconds
                let extraMinutes = place.id == input.enginePreferences?.mainSpotID ? 15 : 0
                let minutes = min(1_440, (seconds + 59) / 60 + extraMinutes)
                duration = .init(minimum: minutes, target: minutes, maximum: minutes,
                                 basis: "estimate", source: Self.localDurationSource)
            } else {
                duration = nil
                preflight.unresolved.append(.init(code: "duration_unknown", placeID: place.id))
            }
            var access = await accessHours(place, input: input, preparedHours: preparedHours)
            if ["unknown", "error"].contains(access.kind),
               let estimate = EstimatedVisitWindow(categories: place.categories).interval(on: input.startsAt, timeZone: input.timeZone) {
                access = .init(kind: "estimated", windows: [.init(opens: Int(estimate.start.timeIntervalSince1970 / 60),
                                                                  closes: Int(estimate.end.timeIntervalSince1970 / 60))],
                               source: EstimatedVisitWindow.source)
            }
            var target: V4Target?
            if place.id == remainingVisit?.id {
                target = .init(earliest: earliest, latest: earliest, strength: "hard", origin: "user", source: "active_visit")
            } else if let session = place.activitySession {
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
                                                          latest: midnight + part.minuteRange.upperBound - 1, strength: "soft", origin: "model", source: daypartSource)
            }
            stops.append(.init(id: place.id.uuidString, duration: duration, hours: access, target: target))
        }
        if let requestID { Self.logPhase("access_resolution", since: accessStarted, requestID: requestID) }
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
            if earlyCode == "V4_WINDOW_TOO_SHORT", includesAlternatives {
                await PocketPlanningActivity.show(.travelTimes)
                preflight.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes, preparedHours: preparedHours)
            }
            throw PlanningScheduleFailure(code: earlyCode, assessment: preflight)
        }
        await PocketPlanningActivity.show(.travelTimes)
        let routeStarted = ContinuousClock.now
        defer { if let requestID { Self.logPhase("route_search", since: routeStarted, requestID: requestID) } }
        var result = try await V41Planner.search(trip, input: input, modelTargets: modelTargets, routes: routes)
        guard let selected = result.selected else {
            if includesAlternatives {
                result.assessment.durationAlternatives = try await alternatives(input, semantic: semantic, routes: routes, preparedHours: preparedHours)
            }
            let code = result.assessment.allCandidatesMissedDeadline ? "V4_WINDOW_TOO_SHORT" :
                (result.blockedByRegularHours ? "V41_ACCESS_CONFLICT" : "V41_NO_SCHEDULE")
            throw PlanningScheduleFailure(code: code, assessment: result.assessment)
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
            if place.durationOverridden != true, place.activitySession == nil {
                if selected.assumptions.contains("\(visit.id):estimated_duration:\(Self.localDurationSource)") {
                    stop.warnings.append("Visit duration is estimated by Travelants.")
                } else {
                    stop.warnings.append(onDevice ? "Visit duration is estimated by Foundation Models." : "Visit duration is a Luna estimate.")
                }
            }
            if modelTargets[visit.id] != nil {
                stop.warnings.append(onDevice ? "Preferred activity time is suggested by Foundation Models." : "Preferred activity time is a Luna suggestion.")
            }
            return stop
        }
        guard scheduled.count == input.places.count else { throw PlanningError.invalidResponse }
        let version = input.enginePreferences?.orderingMethod?.usesV42Scheduler == true ? "4.2" : "4.1"
        var proposal = PlanProposal(id: UUID(), input: input, stops: scheduled,
                                    finishesAt: selected.finish.map { Date(timeIntervalSince1970: Double($0 * 60)) }, feasible: true,
                                    explanation: "Hybrid v\(version) checked \(result.assessment.evaluatedCandidates) candidates with departure-specific travel estimates.",
                                    warnings: result.assessment.messages(in: input), evidence: [], synthetic: synthetic)
        if input.enginePreferences?.scheduleSource == .automatic || input.enginePreferences?.scheduleSource == .timingAnswer {
            proposal.input.enginePreferences?.scheduleSource = .resolved
        }
        if input.enginePreferences?.usesAutomaticTripDate == true { proposal.input.enginePreferences?.usesAutomaticTripDate = false }
        proposal.firstItinerary = true
        proposal.departureAt = Date(timeIntervalSince1970: Double(selected.spec.departure * 60))
        proposal.returnTravelSeconds = input.planningEndpoint == nil ? nil : selected.return_quote?.minutes.map { $0 * 60 }
        proposal.experienceRouteCheckedAt = .now
        proposal.experiencePlan = semantic
        proposal.scheduleAssessment = result.assessment
        if onDevice, let semantic { proposal.warnings.append(contentsOf: semantic.contextWarnings) }
        proposal.warnings.append("Regular hours may differ on the selected date. Search uses a finite departure grid and the earliest necessary waiting within your allowance.")
        return proposal
    }

    private func alternatives(_ input: PlanningInput, semantic: PlanningExperiencePlan?, routes: V41RouteSession,
                              preparedHours: [String: PlanningHoursLookup]) async throws -> [PlanningDurationAlternative] {
        guard input.places.allSatisfy({ $0.activitySession != nil || ($0.durationOverridden == true && $0.visitSeconds > 0) || semantic?.stop($0.id)?.duration != nil }) else { return [] }
        // Sensitivity candidates are evaluated once; their recursive alternatives are disabled by exact overrides.
        let choices = input.places.compactMap { place -> PlanningDurationAlternative? in
            guard place.activitySession == nil else { return nil }
            let estimate = semantic?.stop(place.id)?.duration
            let target = place.durationOverridden == true ? place.visitSeconds : (estimate?.suggestedSeconds ?? 0)
            let minimum = place.durationOverridden == true ? place.minimumAcceptedVisitSeconds : estimate.map { $0.minMinutes * 60 }
            guard let minimum, minimum > 0, minimum < target else { return nil }
            let estimatedSource = input.enginePreferences?.orderingMethod == .hybridV42FoundationModels ? "foundation_models_experience_estimate" : "luna_experience_estimate"
            return .init(placeID: place.id, originalSeconds: target, proposedSeconds: minimum,
                         source: place.durationOverridden == true ? "traveller_accepted_minimum" : estimatedSource,
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
            if (try? await schedule(shorter, semantic: semantic, routes: routes, preparedHours: preparedHours, includesAlternatives: false)) != nil { return [choice] }
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

    func accessHours(_ place: PlanningPlace, input: PlanningInput, preparedHours: [String: PlanningHoursLookup]) async -> V4Hours {
        if let value = place.visitConfirmation, value.publicAccessConfirmed {
            return .init(kind: "confirmed", windows: [.init(opens: Int(ceil(value.opensAt.timeIntervalSince1970 / 60)),
                                                            closes: Int(floor(value.closesAt.timeIntervalSince1970 / 60)), last_entry: value.lastEntryAt.map { Int(floor($0.timeIntervalSince1970 / 60)) })], source: "traveller_confirmation")
        }
        guard let source = place.sourceID, source.hasPrefix("apple:") else { return .init(kind: "unknown", windows: [], source: nil) }
        let id = String(source.dropFirst(6))
        let lookup: PlanningHoursLookup
        if let prepared = preparedHours[id] { lookup = prepared }
        else { lookup = await hours(id) }
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

    private static func semanticKey(_ input: PlanningInput, method: PlanningOrderingMethod) throws -> String {
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
        let namespace: String
        switch method {
        case .hybridV42FoundationModels: namespace = "v4.2-foundation-models-semantic-v1:"
        case .hybridV51, .hybridV52: namespace = "v5.1-semantic-v1:"
        case .hybridV42: namespace = "v4.2-compact-semantic-v1:"
        default: namespace = "v4.1-semantic-v1:"
        }
        return SHA256.hash(data: Data(namespace.utf8) + data).map { String(format: "%02x", $0) }.joined()
    }

    private func proposalKey(_ proposal: PlanProposal) -> [Int] {
        [proposal.scheduleAssessment?.preferredPeriodOutsideMinutes ?? 0,
         Int((proposal.finishesAt ?? proposal.input.finishBy).timeIntervalSince(proposal.departureAt ?? proposal.input.startsAt) / 60)]
    }
}
