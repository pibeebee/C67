import Foundation

public enum VisitGoal: String, Codable, CaseIterable, Sendable { case preferredTime, lowerRain, quiet, comfortableTemperature }
public enum ActivityExposure: String, Codable, Sendable { case indoor, outdoor, mixed, unknown }
public struct PreferredVisitTime: Codable, Sendable {
    public var earliest: Int; public var latest: Int; public var required: Bool
    public init(earliest: Int, latest: Int, required: Bool = false) { self.earliest = earliest; self.latest = latest; self.required = required }
}
public struct VisitContextRequest: Codable, Sendable {
    public var placeID: String
    public var identityConfirmed = false
    public var day: String
    public var availableStart = 480
    public var availableEnd = 1140
    public var durationMinutes = 60
    public var startStepMinutes = 15
    public var preferredTime: PreferredVisitTime?
    public var seeksQuiet = false
    public var avoidRain = false
    public var maximumComfortTemperatureC: Double?
    public var exposure = ActivityExposure.unknown
    public var exposureEvidence: String?
    public var allowRegularHours = true
    public var priorities: [VisitGoal] = [.preferredTime, .lowerRain, .quiet, .comfortableTemperature]
    public init(placeID: String, day: String) { self.placeID = placeID; self.day = day }
    enum CodingKeys: String, CodingKey { case placeID, identityConfirmed, day, availableStart, availableEnd, durationMinutes, startStepMinutes, preferredTime, seeksQuiet, avoidRain, maximumComfortTemperatureC, exposure, exposureEvidence, allowRegularHours, priorities }
    public init(from decoder: Decoder)throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placeID = try c.decode(String.self, forKey: .placeID); day = try c.decode(String.self, forKey: .day)
        identityConfirmed = try c.decodeIfPresent(Bool.self, forKey: .identityConfirmed) ?? false
        availableStart = try c.decodeIfPresent(Int.self, forKey: .availableStart) ?? 480
        availableEnd = try c.decodeIfPresent(Int.self, forKey: .availableEnd) ?? 1140
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60
        startStepMinutes = try c.decodeIfPresent(Int.self, forKey: .startStepMinutes) ?? 15
        preferredTime = try c.decodeIfPresent(PreferredVisitTime.self, forKey: .preferredTime)
        seeksQuiet = try c.decodeIfPresent(Bool.self, forKey: .seeksQuiet) ?? false
        avoidRain = try c.decodeIfPresent(Bool.self, forKey: .avoidRain) ?? false
        maximumComfortTemperatureC = try c.decodeIfPresent(Double.self, forKey: .maximumComfortTemperatureC)
        exposure = try c.decodeIfPresent(ActivityExposure.self, forKey: .exposure) ?? .unknown
        exposureEvidence = try c.decodeIfPresent(String.self, forKey: .exposureEvidence)
        allowRegularHours = try c.decodeIfPresent(Bool.self, forKey: .allowRegularHours) ?? true
        priorities = try c.decodeIfPresent([VisitGoal].self, forKey: .priorities) ?? [.preferredTime, .lowerRain, .quiet, .comfortableTemperature]
    }
    public var goals: [VisitGoal] { priorities.filter {
        switch $0 {
        case .preferredTime: preferredTime != nil
        case .lowerRain: avoidRain
        case .quiet: seeksQuiet
        case .comfortableTemperature: maximumComfortTemperatureC != nil
        }
    }}
    public func validate() throws {
        guard GooglePlacesClient.validID(placeID), ContextClock.day(day) != nil, (0 ... 1439).contains(availableStart),
              (1 ... 1440).contains(availableEnd), availableStart < availableEnd, (15 ... 360).contains(durationMinutes), durationMinutes.isMultiple(of: 15),
              [1, 5, 15].contains(startStepMinutes),
              priorities.count <= 4, Set(priorities).count == priorities.count,
              (!avoidRain || priorities.contains(.lowerRain)), (!seeksQuiet || priorities.contains(.quiet)),
              (preferredTime == nil || priorities.contains(.preferredTime)),
              (maximumComfortTemperatureC == nil || priorities.contains(.comfortableTemperature)),
              maximumComfortTemperatureC.map({ $0.isFinite && (-20 ... 60).contains($0) }) ?? true
        else { throw ContextError.invalid("Invalid visit request: Jakarta date, 15-minute dwell, bounds and active priorities required") }
        if let p = preferredTime { guard (0 ... 1439).contains(p.earliest), (0 ... 1439).contains(p.latest), p.earliest <= p.latest else { throw ContextError.invalid("Preferred visit-start window invalid") } }
        if exposure != .unknown && (exposureEvidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw ContextError.invalid("Indoor/outdoor classification requires explicit area/activity evidence or a user statement")
        }
    }
}
public enum ContextClock {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jakarta")!; return c }
    public static func day(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, text.count == 10, (2020 ... 2100).contains(parts[0]), (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]),
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year == parts[0] && c.month == parts[1] && c.day == parts[2] && label(date) == text ? date : nil
    }
    public static func label(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
public struct WeatherContextHour: Codable, Sendable {
    public var start: Date; public var rainProbability: Double?; public var temperatureC: Double?
    public init(start: Date, rainProbability: Double?, temperatureC: Double?) { self.start = start; self.rainProbability = rainProbability; self.temperatureC = temperatureC }
}
public struct VisitWeatherContext: Codable, Sendable {
    public var source: String; public var fetchedAt: Date; public var expiresAt: Date; public var hours: [WeatherContextHour]
    public init(source: String, fetchedAt: Date, expiresAt: Date, hours: [WeatherContextHour]) { self.source = source; self.fetchedAt = fetchedAt; self.expiresAt = expiresAt; self.hours = hours }
}
public struct OperatingInterval: Codable, Sendable {
    public var start: Date; public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}
public struct OperatingResolution: Codable, Sendable {
    public var state: String; public var source: String; public var intervals: [OperatingInterval]; public var warnings: [String]
}
public enum GoogleHoursResolver {
    public static func resolve(_ snapshot: PlaceSnapshot, day: String, allowRegular: Bool, now: Date) -> OperatingResolution {
        func unknown(_ why: String) -> OperatingResolution { .init(state: "unknown", source: snapshot.source, intervals: [], warnings: [why]) }
        guard snapshot.fetchedAt <= now.addingTimeInterval(300), snapshot.expiresAt > now else { return unknown("Place snapshot stale or future-dated; fetch again") }
        guard let target = ContextClock.day(day) else { return unknown("Invalid day") }
        let place = snapshot.place
        guard place.timeZone?.id == "Asia/Jakarta" || (place.timeZone?.id == nil && place.utcOffsetMinutes == 420) else { return unknown("Pilot requires verified Asia/Jakarta timezone or UTC+07:00 offset") }
        if let state = place.businessStatus, state != "OPERATIONAL" {
            if ["CLOSED_TEMPORARILY", "CLOSED_PERMANENTLY"].contains(state) { return .init(state: "closed", source: "Google businessStatus", intervals: [], warnings: [state]) }
            return unknown("Business status not operational")
        }
        guard place.businessStatus == "OPERATIONAL" else { return unknown("Business status unknown") }
        let today = ContextClock.calendar.startOfDay(for: snapshot.fetchedAt)
        let coverageEnd = ContextClock.calendar.date(byAdding: .day, value: 7, to: today)!
        let current = target >= today && target < coverageEnd && place.currentOpeningHours != nil
        guard let hours = current ? place.currentOpeningHours : (allowRegular ? place.regularOpeningHours : nil), let periods = hours.periods else { return unknown("Opening periods unavailable; openNow is not a daily schedule") }
        let end = target.addingTimeInterval(86400)
        var result: [OperatingInterval] = []; var malformed = false
        func minute(_ p: PlacesPoint) -> Int? {
            let h = p.hour ?? 0; let m = p.minute ?? 0
            guard (0 ... 23).contains(h), (0 ... 59).contains(m), (0 ... 6).contains(p.day ?? 0) else { return nil }; return h * 60 + m
        }
        func dated(_ p: PlacesPoint) -> Date? {
            guard let d = p.date, let y = d.year, let m = d.month, let day = d.day, let minutes = minute(p),
                  let base = ContextClock.day(String(format: "%04d-%02d-%02d", y, m, day)) else { return nil }
            return base.addingTimeInterval(Double(minutes * 60))
        }
        for period in periods {
            guard let open = period.open, let om = minute(open) else { malformed = true; continue }
            if period.close == nil {
                if periods.count == 1 && (open.day ?? 0) == 0 && om == 0 && open.date == nil { result.append(.init(start: target, end: end)) }
                else { malformed = true }; continue
            }
            let close = period.close!; guard let cm = minute(close) else { malformed = true; continue }
            var ranges: [(Date, Date)] = []
            if open.date != nil || close.date != nil {
                guard let a = dated(open), let b = dated(close), b > a else { malformed = true; continue }; ranges = [(a, b)]
            } else {
                let weekday = ContextClock.calendar.component(.weekday, from: target) - 1
                let week = target.addingTimeInterval(Double(-weekday * 86400))
                let from = (open.day ?? 0) * 1440 + om
                var to = (close.day ?? 0) * 1440 + cm
                if to == from { malformed = true; continue }
                if to < from { to += 7 * 1440 }
                for shift in [-7, 0, 7] { ranges.append((week.addingTimeInterval(Double((shift * 1440 + from) * 60)), week.addingTimeInterval(Double((shift * 1440 + to) * 60)))) }
            }
            for (a, b) in ranges where a < end && b > target { result.append(.init(start: max(a, target), end: min(b, end))) }
        }
        if malformed { return unknown("Malformed/incomplete period; no closing time invented") }
        var warnings = current ? ["Google current hours, including supplied exceptions; last entry/reservations may still be unknown"] : ["Regular weekly hours only; holiday/date exceptions unconfirmed"]
        if periods.contains(where: { $0.open?.truncated == true || $0.close?.truncated == true }) { warnings.append("Provider truncated periods; do not extend beyond returned bounds") }
        return .init(state: result.isEmpty ? "closed" : "available", source: current ? "Google currentOpeningHours" : "Google regularOpeningHours", intervals: result.sorted { $0.start < $1.start }, warnings: warnings)
    }
}
public struct ReviewTimeHint: Codable, Sendable {
    public var reviewID: String; public var aspect: String; public var timeBand: String; public var dayKind: String
    public var author: PlacesAuthor?; public var url: String?; public var publishedAt: String?
    public var evidenceKind = "single_review_indication"; public var interpretation = "Rule-based id/en extraction; not public consensus or verified occupancy"
}
public enum ReviewTimeExtractor {
    public static func extract(_ reviews: [PlacesReview], now: Date) -> [ReviewTimeHint] {
        var hints: [ReviewTimeHint] = []; var seen = Set<String>()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (index, r) in reviews.prefix(5).enumerated() {
            let id = r.name ?? "review-\(index)"; guard seen.insert(id).inserted else { continue }
            guard let stamp = r.publishTime, let published = iso.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp), now.timeIntervalSince(published) >= (-300), now.timeIntervalSince(published) <= 180 * 86400 else { continue }
            let original = r.originalText
            let used = (original?.languageCode.map { $0.hasPrefix("id") || $0.hasPrefix("en") } ?? true) ? (original ?? r.text) : r.text
            guard let raw = used?.text, (used?.languageCode.map { $0.hasPrefix("id") || $0.hasPrefix("en") } ?? true) else { continue }
            let text = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "id_ID"))
            for clause in text.components(separatedBy: CharacterSet(charactersIn: ".!?;,\n")) {
                func has(_ pattern: String) -> Bool { clause.range(of: pattern, options: .regularExpression) != nil }
                if has("tidak tahu|belum pernah|not sure|maybe|mungkin|tidak sepi|not quiet") { continue }
                let bands = [("morning", "\\b(pagi|morning)\\b"), ("afternoon", "\\b(sore|afternoon)\\b"), ("evening", "\\b(malam|evening|night)\\b")].filter { has($0.1) }
                guard bands.count == 1 else { continue } // No time inferred from publishTime/visitDate/stars.
                let negativeBusy = has("(tidak|nggak|gak|not)\\s+(terlalu\\s+)?(ramai|crowded|busy)")
                let quiet = negativeBusy || has("\\b(sepi|tenang|quiet|calm)\\b")
                let busy = !negativeBusy && has("\\b(ramai|crowded|busy)\\b")
                guard quiet != busy else { continue }
                let weekend = has("akhir pekan|weekend|sabtu|minggu|saturday|sunday")
                let weekday = has("hari kerja|weekday|senin|selasa|rabu|kamis|jumat|monday|tuesday|wednesday|thursday|friday")
                if weekend && weekday { continue }
                hints.append(.init(reviewID: id, aspect: quiet ? "quiet" : "busy", timeBand: bands[0].0, dayKind: weekend ? "weekend" : weekday ? "weekday" : "unspecified", author: r.authorAttribution, url: r.googleMapsUri, publishedAt: r.publishTime))
            }
        }
        return hints
    }
}
public struct GoalAssessment: Codable, Sendable { public var goal: VisitGoal; public var penalty: Double?; public var explanation: String }
public struct VisitContextOption: Codable, Sendable {
    public var start: Date; public var end: Date; public var assessments: [GoalAssessment]; public var evidenceReviewIDs: [String]
    public var unknowns: [String]
    public var rank: [Double] { assessments.map { $0.penalty ?? 10000 } }
}
public struct VisitContextResult: Codable, Sendable {
    public var status: String; public var placeID: String; public var source: String; public var hours: OperatingResolution
    public var options: [VisitContextOption]; public var reviewHints: [ReviewTimeHint]; public var warnings: [String]
    public var attribution: String; public var googleMapsURI: String?; public var providerAttributions: [PlacesAttribution]
    public var reviewAttributions: [PlacesReview]
}
public enum VisitContextEngine {
    public static func evaluate(snapshot: PlaceSnapshot, request: VisitContextRequest, weather: VisitWeatherContext? = nil, now: Date = .now)throws -> VisitContextResult {
        try request.validate()
        guard snapshot.place.id == request.placeID else { throw ContextError.invalid("Place identity mismatch") }
        let hours = GoogleHoursResolver.resolve(snapshot, day: request.day, allowRegular: request.allowRegularHours, now: now)
        let hints = ReviewTimeExtractor.extract(snapshot.place.reviews ?? [], now: now)
        var result = VisitContextResult(status: "needs_identity_confirmation", placeID: request.placeID, source: snapshot.source, hours: hours, options: [], reviewHints: hints,
                                        warnings: hours.warnings + ["At most five returned reviews; no popular-times, queue, ideal-duration or public-consensus claim", "Unknown attributes remain unknown; outdoorSeating does not classify the requested activity"],
                                        attribution: snapshot.attribution, googleMapsURI: snapshot.place.googleMapsUri, providerAttributions: snapshot.place.attributions ?? [], reviewAttributions: snapshot.place.reviews ?? [])
        guard request.identityConfirmed else { return result }
        guard hours.state == "available" else { result.status = hours.state == "closed" ? "closed" : "needs_hours"; return result }
        let midnight = ContextClock.day(request.day)!
        let validWeather = weather.flatMap { w -> VisitWeatherContext? in
            let sorted = w.hours.sorted { $0.start < $1.start }
            guard !w.source.isEmpty, w.fetchedAt <= now.addingTimeInterval(300), w.expiresAt > now,
                  zip(sorted, sorted.dropFirst()).allSatisfy({ $1.start.timeIntervalSince($0.start) >= 3600 }) else { return nil }
            return w
        }
        func coverage(_ start: Date, _ end: Date) -> (Double?, Double?) {
            guard let w = validWeather else { return (nil, nil) }
            var cursor = start; var rain: [Double] = []; var temperatures: [Double] = []; var rainComplete = true; var temperatureComplete = true
            while cursor < end {
                guard let hour = w.hours.first(where: { $0.start <= cursor && $0.start.addingTimeInterval(3600) > cursor }) else { return (nil, nil) }
                if let p = hour.rainProbability, p.isFinite, (0 ... 1).contains(p) { rain.append(p) } else { rainComplete = false }
                if let t = hour.temperatureC, t.isFinite, (-90 ... 65).contains(t) { temperatures.append(t) } else { temperatureComplete = false }
                cursor = min(end, hour.start.addingTimeInterval(3600))
            }
            return (rainComplete ? rain.max() : nil, temperatureComplete ? temperatures.max() : nil)
        }
        let weekday = ContextClock.calendar.component(.weekday, from: midnight); let kind = [1, 7].contains(weekday) ? "weekend" : "weekday"
        let step = request.startStepMinutes
        let lower = ((request.availableStart + step - 1) / step) * step
        for minute in stride(from: lower, through: request.availableEnd, by: step) {
            let start = midnight.addingTimeInterval(Double(minute * 60)), end = start.addingTimeInterval(Double(request.durationMinutes * 60))
            guard minute + request.durationMinutes <= request.availableEnd, start >= now,
                  hours.intervals.contains(where: { start >= $0.start && end <= $0.end }) else { continue }
            if let p = request.preferredTime, p.required,!(p.earliest ... p.latest).contains(minute) { continue }
            let (rain, temp) = coverage(start, end)
            var unknowns: [String] = []; var assessments: [GoalAssessment] = []; var evidenceIDs = Set<String>()
            for goal in request.goals {
                var penalty: Double?; var explanation = ""
                switch goal {
                case .preferredTime:
                    let p = request.preferredTime!; penalty = Double(max(0, max(p.earliest - minute, minute - p.latest)))
                    explanation = "Distance in minutes from user-provided visit-start preference"
                case .lowerRain:
                    if request.exposure == .indoor { penalty = 0; explanation = "User/sourced activity is indoors; access and transfers are not covered" }
                    else if request.exposure == .outdoor, let rain { penalty = rain * 100; explanation = "Maximum hourly rain probability over full visit; not a guarantee" }
                    else { unknowns.append("Rain preference cannot be assessed: activity exposure or full forecast coverage missing") }
                case .comfortableTemperature:
                    if request.exposure == .outdoor, let temp { penalty = max(0, temp - request.maximumComfortTemperatureC!); explanation = "Degrees above user maximum over full visit" }
                    else { unknowns.append("Thermal comfort unknown: forecast, outdoor activity or indoor conditions missing") }
                case .quiet:
                    // Qualitative bands are application interpretation, never precise observed occupancy.
                    let band = (360 ..< 660).contains(minute) ? "morning" : (900 ..< 1080).contains(minute) ? "afternoon" : (1080 ..< 1320).contains(minute) ? "evening" : "unspecified"
                    let bandEnd = band == "morning" ? 660 : band == "afternoon" ? 1080 : band == "evening" ? 1320 : 0
                    let applicable = hints.filter { minute + request.durationMinutes <= bandEnd && $0.timeBand == band && ($0.dayKind == kind || $0.dayKind == "unspecified") }
                    let positive = applicable.contains { $0.aspect == "quiet" }; let negative = applicable.contains { $0.aspect == "busy" }
                    if positive != negative {
                        penalty = positive ? 0 : 1; explanation = "Weak review indication for a qualitative time band; not measured crowd data"
                        evidenceIDs.formUnion(applicable.map(\.reviewID))
                    } else { unknowns.append("Quietness unknown or conflicting for this time/day; stars are not evidence") }
                }
                assessments.append(.init(goal: goal, penalty: penalty, explanation: explanation.isEmpty ? "Insufficient context" : explanation))
            }
            result.options.append(.init(start: start, end: end, assessments: assessments, evidenceReviewIDs: evidenceIDs.sorted(), unknowns: unknowns))
        }
        result.options.sort { a, b in a.rank == b.rank ? a.start < b.start : a.rank.lexicographicallyPrecedes(b.rank) }
        result.status = result.options.isEmpty ? "no_feasible_visit_window" : request.goals.isEmpty ? "operating_hours_options" : result.options.allSatisfy({ $0.unknowns.isEmpty }) ? "context_options" : "options_with_unknowns"
        if !hints.isEmpty { result.warnings.append("Review hints are rule-based hypotheses; morning=06–11, afternoon=15–18, evening=18–22, not observed hourly counts") }
        return result
    }
}
