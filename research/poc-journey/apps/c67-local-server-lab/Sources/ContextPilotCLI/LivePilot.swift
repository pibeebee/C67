import Foundation
import PlaceContextEngine
import PlannerEngine
import ContextPilotAdapters

@MainActor enum LivePilot {
    struct Target {
        var id: String; var query: String; var googleAliases: [String]; var appleAliases: [String]
        var lat: Double; var lon: Double; var dwell: Int; var exposure: ActivityExposure
    }
    struct IdentityRecord: Codable {
        var internalID: String; var googleID: String?; var appleName: String; var appleLatitude: Double; var appleLongitude: Double
        var evidence: String; var reviews: Int; var timeHints: Int; var hoursStatus: String; var operatingWindowsWIB: [String]
    }
    struct LiveReport: Codable {
        var startedAt: Date; var completedAt: Date; var day: String; var departureWIB: String; var deadlineWIB: String
        var actualUserBrief: String; var assumptions: String; var evidenceMode: String
        var discoverySeconds: Double; var enrichmentSeconds: Double; var completeCLISeconds: Double
        var googleCalls: Int; var appleHTTPCalls: Int; var appleETACells: Int
        var identities: [IdentityRecord]; var weatherStatus: String; var weatherAttribution: String?
        var weatherRainRange: [Double]; var rows: [PilotRow]; var hardAuditPassed: Int
        var humanValidation: String; var limitations: [String]
        var stopDurations: [String: Int] = [:]; var departureMinute = 660; var deadlineMinute = 1140
        var maximumWaitingMinutes = 30; var beamWidth = 12; var inputOrder: [String] = []
    }
    static func minute(_ date: Date) -> Int { let c = ContextClock.calendar.dateComponents([.hour, .minute], from: date); return c.hour! * 60 + c.minute! }
    static func time(_ date: Date) -> String { let m = minute(date); return String(format: "%02d:%02d", m / 60, m % 60) }
    static func normalized(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")) }
    static func match(_ name: String, _ aliases: [String]) -> Bool { let n = normalized(name); return aliases.contains { n.contains(normalized($0)) } }
    static func distance(_ lat: Double, _ lon: Double, _ t: Target) -> Double {
        let x = (lat - t.lat) * 111000; let y = (lon - t.lon) * 110000; return sqrt(x * x + y * y)
    }
    static func save<T: Encodable>(_ value: T, _ directory: URL, _ name: String)throws {
        try ContextJSON.encoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    static func audit(_ result: ContextItineraryResult, _ input: ContextPlanRequest)throws {
        let readyStatuses = ["candidate", "candidate_with_unknown_preferences"]
        guard !result.visits.isEmpty else {
            let emptyStatuses = ["needs_context", "no_candidate_within_search", "incomplete_travel_data"]
            guard emptyStatuses.contains(result.status), result.legs.isEmpty, result.finish == nil else {
                throw ContextError.invalid("Live audit found inconsistent empty result")
            }
            return
        }
        guard readyStatuses.contains(result.status) else {
            throw ContextError.invalid("Live audit found visits with a non-ready status")
        }
        func require(_ value: Bool, _ reason: String)throws { if !value { throw ContextError.invalid("Live audit: " + reason) } }
        try require(result.visits.count == input.stops.count && Set(result.visits.map(\.placeID)) == Set(input.stops.map { $0.request.placeID }), "stop coverage")
        try require(result.legs.count == result.visits.count + 1, "leg count")
        var cursor = input.departure; var last = input.originID; var wait = 0.0; var travel = 0.0; var dwell = 0.0
        for (index, visit) in result.visits.enumerated() {
            let leg = result.legs[index]; let request = input.stops.first { $0.request.placeID == visit.placeID }!.request
            try require(leg.from == last && leg.to == visit.placeID && abs(leg.departure.timeIntervalSince(cursor)) < 0.001, "leg continuity")
            try require(abs(leg.evidence.departure.timeIntervalSince(cursor)) < 0.001 && leg.evidence.source.hasPrefix("Apple"), "evidence departure/source")
            try require(abs(leg.arrival.timeIntervalSince(leg.departure) - leg.evidence.seconds) < 0.001 && abs(visit.arrival.timeIntervalSince(leg.arrival)) < 0.001, "ETA arithmetic")
            try require(visit.visit.start >= visit.arrival && abs(visit.visit.end.timeIntervalSince(visit.visit.start) - Double(request.durationMinutes * 60)) < 0.001, "arrival/full dwell")
            // Uses the returned operating bounds: consistency audit, not independent field-hours verification.
            let context = result.contexts.first { $0.placeID == visit.placeID }!
            try require(context.hours.intervals.contains { visit.visit.start >= $0.start && visit.visit.end <= $0.end }, "operating bounds")
            wait += visit.visit.start.timeIntervalSince(visit.arrival); travel += leg.evidence.seconds; dwell += Double(request.durationMinutes * 60)
            cursor = visit.visit.end; last = visit.placeID
        }
        let back = result.legs.last!
        try require(back.from == last && back.to == input.returnID && abs(back.departure.timeIntervalSince(cursor)) < 0.001, "return")
        try require(abs(back.evidence.departure.timeIntervalSince(cursor)) < 0.001 && abs(back.arrival.timeIntervalSince(cursor) - back.evidence.seconds) < 0.001, "return ETA")
        travel += back.evidence.seconds
        try require(back.arrival <= input.deadline && result.finish == back.arrival, "deadline")
        try require(wait <= Double((input.maximumTotalWaitingMinutes ?? 1440) * 60) + 0.001 && abs(result.waitingSeconds - wait) < 0.001, "waiting cap")
        try require(abs(result.travelSeconds - travel) < 0.001 && abs(result.dwellSeconds - dwell) < 0.001 && abs((result.elapsedSeconds ?? -1) - back.arrival.timeIntervalSince(input.departure)) < 0.001, "totals")
    }
    static func run(directory: URL, single: Bool = false, five: Bool = false, diagnosticWaiting: Int? = nil) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let start = Date(); let began = ContinuousClock.now
        let now = Date(); let midnight = ContextClock.calendar.startOfDay(for: now)
        let dayBase = ContextClock.calendar.date(byAdding: .day, value: 1, to: midnight)!; let day = ContextClock.label(dayBase)
        var targets = [
            Target(id: "museum", query: "Museum Nasional Indonesia Jakarta", googleAliases: ["Museum Nasional Indonesia"], appleAliases: ["Museum Nasional", "National Museum"], lat: -6.1764, lon: 106.822, dwell: 90, exposure: .indoor),
            Target(id: "gallery", query: "Museum Bank Indonesia Jakarta", googleAliases: ["Museum Bank Indonesia", "Bank Indonesia Museum"], appleAliases: ["Museum Bank Indonesia", "Bank Indonesia Museum", "Museum BI"], lat: -6.1372, lon: 106.8132, dwell: 60, exposure: .indoor),
            Target(id: "park", query: "Taman Lapangan Banteng Jakarta", googleAliases: ["Lapangan Banteng"], appleAliases: ["Lapangan Banteng"], lat: -6.1705, lon: 106.835, dwell: 60, exposure: .outdoor)]
        if five {
            targets.insert(Target(id: "arts", query: "Fine Arts and Ceramics Museum", googleAliases: ["Museum Seni Rupa dan Keramik", "Fine Art and Ceramic Museum", "Fine Arts and Ceramics Museum"], appleAliases: ["Museum Seni Rupa dan Keramik", "Fine Art and Ceramic Museum", "Fine Arts and Ceramics Museum"], lat: -6.1342607, lon: 106.8144771, dwell: 60, exposure: .indoor), at: 2)
            targets.insert(Target(id: "history", query: "Jakarta History Museum", googleAliases: ["Museum Sejarah Jakarta", "Museum Fatahillah", "Jakarta History Museum"], appleAliases: ["Museum Sejarah Jakarta", "Museum Fatahillah", "Jakarta History Museum"], lat: -6.1352, lon: 106.8133, dwell: 60, exposure: .indoor), at: 3)
        }
        let departureMinute = five ? 540 : 660
        let origin = Target(id: "origin", query: "Hotel Indonesia Kempinski Jakarta", googleAliases: [], appleAliases: ["Hotel Indonesia Kempinski", "Kempinski"], lat: -6.1965, lon: 106.8229, dwell: 0, exposure: .unknown)
        let budget = LabProviderBudget(callLimit: five ? (single ? 140 : 1100) : (single ? 241 : 360), cellLimit: five ? (single ? 64 : 936) : (single ? 128 : 240))
        let apple = LabAppleREST(config: try .init(), budget: budget)
        let search = LabRESTSearch(apple: apple)
        let google = GooglePlacesClient(configuration: try .init(apiKey: ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"] ?? "", maxRequests: five ? 10 : (single ? 6 : 12)))
        defer { try? save(["googleCalls": google.requests, "appleHTTPCalls": budget.calls, "appleETACells": budget.cells], directory, "budget-checkpoint.json") }
        var identities: [PilotIdentity] = []; var googleIDs: [String: String] = [:]
        let seedURL = directory.deletingLastPathComponent().appendingPathComponent("reuse-google-ids.json")
        let seededIDs: [String: String] = five && (!single || diagnosticWaiting != nil) && FileManager.default.fileExists(atPath: seedURL.path)
            ? try JSONDecoder().decode([String: String].self, from: Data(contentsOf: seedURL)) : [:]
        guard seededIDs.allSatisfy({ ["museum", "gallery", "arts", "history", "park"].contains($0.key) && GooglePlacesClient.validID($0.value) }) else { throw ContextError.invalid("Invalid pinned Google identity seed") }
        let discoveryBegan = ContinuousClock.now
        for t in targets + [origin] {
            let pins = try await search.search(query: t.query)
            try save(pins, directory, "apple-search-" + t.id + ".json")
            let matches = pins.filter { match($0.name, t.appleAliases) && distance($0.latitude, $0.longitude, t) < (t.id == "history" ? 100 : 800) }
            guard matches.count == 1, let pin = matches.first else { throw ContextError.invalid("Unresolved Apple identity for \(t.id): \(matches.count) eligible matches; no silent selection") }
            var googleID: String?
            if let seeded = seededIDs[t.id] { googleID = seeded; googleIDs[t.id] = seeded }
            else if t.id != "origin" {
                let places = try await google.search(t.query, limit: 5)
                let valid = places.filter { p in
                    guard let name = p.displayName?.text, let point = p.location else { return false }
                    return match(name, t.googleAliases) && distance(point.latitude, point.longitude, t) < (t.id == "history" ? 100 : 800)
                }
                guard valid.count == 1, let found = valid.first?.id else { throw ContextError.invalid("Unresolved Google identity for \(t.id)") }
                googleID = found; googleIDs[t.id] = found
            }
            identities.append(.init(internalID: t.id, googlePlaceID: googleID, applePin: pin,
                                    evidence: "Operator-authored alias + Jakarta area gate; independently searched provider identities. Operator is experiment harness, not user confirmation of entrances.", confirmedAt: Date()))
        }
        let discoverySeconds = wall(discoveryBegan)
        // Mapping is small and excludes Google coordinates/reviews; persist a diagnostic checkpoint.
        try save(identities, directory, "identity-checkpoint.json")
        let enrichBegan = ContinuousClock.now
        var snapshots: [String: PlaceSnapshot] = [:]; var records: [IdentityRecord] = []
        for t in targets {
            var s = try await google.details(googleIDs[t.id]!, includeReviews: true, now: Date())
            guard let name = s.place.displayName?.text, let point = s.place.location,
                  match(name, t.googleAliases), distance(point.latitude, point.longitude, t) < (t.id == "history" ? 100 : 800) else { throw ContextError.invalid("Fresh details did not confirm seeded Google identity") }
            // Use internal app IDs for scheduling and routing; retain original Google ID only in explicit mapping.
            s.place.id = t.id; snapshots[t.id] = s
            let hours = GoogleHoursResolver.resolve(s, day: day, allowRegular: false, now: Date())
            let identity = identities.first { $0.internalID == t.id }!
            records.append(.init(internalID: t.id, googleID: googleIDs[t.id], appleName: identity.applePin.name, appleLatitude: identity.applePin.latitude, appleLongitude: identity.applePin.longitude, evidence: identity.evidence, reviews: s.place.reviews?.count ?? 0, timeHints: ReviewTimeExtractor.extract(s.place.reviews ?? [], now: Date()).count, hoursStatus: hours.state, operatingWindowsWIB: hours.intervals.map { time($0.start) + "–" + (ContextClock.label($0.end) != day ? "24:00" : time($0.end)) }))
        }
        let parkPin = identities.first { $0.internalID == "park" }!.applePin
        let weatherEvidence = try await LabRESTWeather(apple: apple).fetch(pin: parkPin, memberIDs: ["park"], start: dayBase.addingTimeInterval(Double((departureMinute / 60 - 1) * 3600)), end: dayBase.addingTimeInterval(20 * 3600), allowFallback: false, now: Date())
        let weather = AppleContextWeatherAdapter.convert(weatherEvidence)
        let enrichmentSeconds = wall(enrichBegan)
        try save(records, directory, "enrichment-checkpoint.json")
        var stops: [ContextPlanStop] = []
        for t in targets {
            var request = VisitContextRequest(placeID: t.id, day: day)
            request.identityConfirmed = true; request.durationMinutes = t.dwell; request.availableStart = departureMinute; request.availableEnd = 19 * 60
            request.allowRegularHours = false; request.exposure = t.exposure
            request.exposureEvidence = t.exposure == .outdoor ? "Pilot activity: walk in open park; operator park description" : "Pilot activity scoped to interior museum galleries; entrance/transfers not classified"
            if t.id == "park" { request.preferredTime = .init(earliest: 15 * 60, latest: 16 * 60) }
            stops.append(.init(snapshot: snapshots[t.id]!, request: request, weather: t.id == "park" ? weather : nil))
        }
        var primary = ContextPlanRequest(originID: "origin", returnID: "origin", departure: dayBase.addingTimeInterval(Double(departureMinute * 60)), deadline: dayBase.addingTimeInterval(19 * 3600), stops: stops)
        primary.maximumTotalWaitingMinutes = diagnosticWaiting ?? 30; primary.allVisitSlots = true; primary.beamWidth = diagnosticWaiting == nil ? 12 : 1
        if diagnosticWaiting != nil {
            let order = ["gallery", "arts", "history", "museum", "park"]
            primary.stops.sort { order.firstIndex(of: $0.request.placeID)! < order.firstIndex(of: $1.request.placeID)! }
        }
        var rows: [PilotRow] = []; var audited = 0
        var configurations: [(String, ContextSearchPolicy, Int, Int)] = []
        if five {
            if single { configurations = [("n5-user-cold", .firstFeasible, 64, 5)] }
            else {
                for rep in 0 ..< 3 {
                    let sizes = rep.isMultiple(of: 2) ? [3, 5] : [5, 3]
                    let policies = rep.isMultiple(of: 2) ? ContextSearchPolicy.allCases : Array(ContextSearchPolicy.allCases.reversed())
                    for n in sizes { configurations += policies.map { ("n\(n)-user-r\(rep + 1)", $0, n == 5 ? 64 : 24, n) } }
                }
                configurations += [("n5-elapsed", .firstFeasible, 24, 5), ("n5-weather_diagnostic", .firstFeasible, 24, 5), ("n5-exploratory-probe", .beam, 96, 5)]
            }
        } else {
            for rep in 0 ..< 3 {
                let order = rep.isMultiple(of: 2) ? ContextSearchPolicy.allCases : Array(ContextSearchPolicy.allCases.reversed())
                configurations += order.map { ("user-r\(rep + 1)", $0, 24, 3) }
            }
            configurations += [("elapsed", .firstFeasible, 12, 3), ("weather_diagnostic", .firstFeasible, 12, 3)]
            if single { configurations = [("user-cold", .firstFeasible, 24, 3)] }
        }
        for (label, policy, cap, n) in configurations {
            if label == "n5-exploratory-probe" {
                let main = rows.filter { $0.stopCount == 5 && $0.caseID.contains("user-r") }
                let allReady = main.allSatisfy { !$0.result.visits.isEmpty }
                let best = main.compactMap { $0.result.penaltyByPriority.first }.min()
                if allReady && best == 0 { continue }
            }
            var input = primary; input.policy = policy; input.maxTravelCalls = cap
            if n == 3 { input.stops.removeAll { !["museum", "gallery", "park"].contains($0.request.placeID) } }
            if label.hasSuffix("elapsed") { for i in input.stops.indices { input.stops[i].request.preferredTime = nil } }
            if label.hasSuffix("weather_diagnostic"), let park = input.stops.firstIndex(where: { $0.request.placeID == "park" }) { input.stops[park].request.avoidRain = true }
            let rawETA = LabRESTETA(apple: apple)
            let eta: any LabETAProvider
            if diagnosticWaiting != nil { eta = DiagnosticETA(provider: rawETA, output: directory.appendingPathComponent("eta-trace.json")) }
            else { eta = rawETA }
            let adapter = try AppleContextTravelAdapter(identities: identities, provider: eta)
            let timer = ContinuousClock.now
            var result = try await ContextItineraryPlanner.plan(input, provider: adapter, now: Date())
            let processing = wall(timer)
            try audit(result, input); audited += 1
            // Preserve only itinerary/diagnostics, not a repeated Google response or review archive.
            result.contexts = []
            rows.append(.init(caseID: label, split: "live", family: "actual_user_brief", ablation: label, policy: policy.rawValue, budget: cap, processingSeconds: processing, etaWallSeconds: adapter.providerWallSeconds, result: result, stopCount: input.stops.count))
            try save(rows, directory, "live-observations-checkpoint.json")
            print("Completed \(label)/\(policy.rawValue): \(result.status), ETA=\(result.travelCalls), process=\(String(format: "%.2f", processing))s")
            fflush(stdout)
        }
        var report = LiveReport(startedAt: start, completedAt: Date(), day: day, departureWIB: five ? "09:00" : "11:00", deadlineWIB: "19:00", actualUserBrief: "Taman sore; museum fleksibel; total menunggu maksimal 30 menit", assumptions: five ? "Operator-authored5-stop extension: tomorrow09–19 WIB, hotel origin/return, Museum Nasional90min and other4 stops60min each. Sore remains soft start15–16, total waiting hard30min. N3 is paired subset with same09 departure; human review of5-stop output pending." : "Operator-authored: hotel origin/return, tomorrow, 11–19 WIB, museum90+60min, park60min, sore=start15–16. No user confirmation of these assumptions yet.", evidenceMode: "ACTUAL Google Places + Apple Maps Server API + WeatherKit, Mac CLI, no LLM", discoverySeconds: discoverySeconds, enrichmentSeconds: enrichmentSeconds, completeCLISeconds: wall(began), googleCalls: google.requests, appleHTTPCalls: budget.calls, appleETACells: budget.cells, identities: records, weatherStatus: weatherEvidence.status, weatherAttribution: weather?.source, weatherRainRange: [weather?.hours.compactMap(\.rainProbability).min(), weather?.hours.compactMap(\.rainProbability).max()].compactMap { $0 }, rows: rows, hardAuditPassed: audited, humanValidation: "pending actual review; no approval inferred", limitations: ["Named-place discovery, not open-ended recommendation recall", "Operating bounds are Google consistency checks; official sources contain schedule conflicts; admission unknown", "Only park forecast used; waiting and access exposure remain unknown", "Three repetitions, no p95/SLA or representative accuracy", "Adapted methods, not historical D/E; shared cap is not identical actual cell expenditure", "All place/weather snapshots shared within this live campaign, ETA caches per plan only"])
        report.stopDurations = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.dwell) }); report.departureMinute = departureMinute
        report.maximumWaitingMinutes = diagnosticWaiting ?? 30; report.beamWidth = primary.beamWidth; report.inputOrder = primary.stops.map { $0.request.placeID }
        if let wait = diagnosticWaiting { report.assumptions += " DIAGNOSTIC: geographically authored input order, beamWidth1, total waiting cap\(wait)min. A60min cap is a counterfactual and does not satisfy the actual30min user limit. Google IDs pinned; details and Apple search/ETA fresh." }
        try save(report, directory, "live-report.json")
    }
}
