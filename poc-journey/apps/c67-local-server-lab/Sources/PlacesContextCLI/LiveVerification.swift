import Foundation
import PlaceContextEngine

/// One actual details request, then local comparisons. Never exports review text/authors or keys.
@MainActor enum LiveContextVerification {
    struct Case: Encodable {
        var name: String; var day: String; var status: String; var options: Int; var firstVisitWIB: String?
        var firstPenalties: [Double?]; var unknownGoals: Int; var hardConstraintsPassed: Bool
        var engineSeconds: Double
    }
    struct Report: Encodable {
        var observedAt: String; var placeID: String; var liveDetailsRequests: Int; var providerSeconds: Double
        var reviewsReturned: Int; var reviewTimeHints: Int; var reviewAuthorsRetained: Bool
        var currentHoursPresent: Bool; var regularHoursPresent: Bool; var timeZonePresent: Bool
        var cases: [Case]; var passed: Bool
        var scope: String = "One live Google Place Details response; local schedule tests, not human preference or field validation. No review text persisted."
    }
    static func run(id: String, client: GooglePlacesClient) async throws -> Report {
        let start = ContinuousClock.now; let now = Date()
        let snapshot = try await client.details(id, includeReviews: true, now: now)
        func seconds(_ from: ContinuousClock.Instant) -> Double {
            let c = from.duration(to: .now).components; return Double(c.seconds) + Double(c.attoseconds) / 1e18
        }
        let providerSeconds = seconds(start)
        let midnight = ContextClock.calendar.startOfDay(for: now)
        var rows: [Case] = []
        for offset in [1, 2] {
            let day = ContextClock.label(ContextClock.calendar.date(byAdding: .day, value: offset, to: midnight)!)
            for name in ["hours_only", "prefer_morning", "prefer_afternoon", "quiet", "rain_exposure_unknown", "required_outside_available", "unconfirmed_identity", "stale_snapshot"] {
                var request = VisitContextRequest(placeID: id, day: day)
                request.identityConfirmed = true; request.availableStart = 9 * 60; request.availableEnd = 19 * 60
                switch name {
                case "prefer_morning": request.preferredTime = .init(earliest: 9 * 60, latest: 10 * 60)
                case "prefer_afternoon": request.preferredTime = .init(earliest: 15 * 60, latest: 16 * 60)
                case "quiet": request.seeksQuiet = true
                case "rain_exposure_unknown": request.avoidRain = true
                case "required_outside_available": request.preferredTime = .init(earliest: 23 * 60, latest: 23 * 60 + 30, required: true)
                case "unconfirmed_identity": request.identityConfirmed = false
                default: break
                }
                var input = snapshot
                if name == "stale_snapshot" { input.expiresAt = now.addingTimeInterval(-1) }
                let began = ContinuousClock.now
                let result = try VisitContextEngine.evaluate(snapshot: input, request: request, now: now)
                var passed = result.options.allSatisfy { option in
                    option.end.timeIntervalSince(option.start) == 3600 && option.start >= now &&
                        option.start >= ContextClock.day(day)!.addingTimeInterval(Double(request.availableStart * 60)) &&
                        option.end <= ContextClock.day(day)!.addingTimeInterval(Double(request.availableEnd * 60)) &&
                        result.hours.intervals.contains { option.start >= $0.start && option.end <= $0.end }
                }
                if name == "required_outside_available" || name == "stale_snapshot" || name == "unconfirmed_identity" { passed = passed && result.options.isEmpty }
                if name == "unconfirmed_identity" { passed = passed && result.status == "needs_identity_confirmation" }
                if name == "stale_snapshot" { passed = passed && result.status == "needs_hours" }
                if let best = result.options.first {
                    passed = passed && result.options.allSatisfy { !($0.rank.lexicographicallyPrecedes(best.rank)) }
                    if let preferred = request.preferredTime {
                        let exact = result.options.contains { o in
                            let minute = Int(o.start.timeIntervalSince(ContextClock.day(day)!) / 60)
                            return (preferred.earliest ... preferred.latest).contains(minute)
                        }
                        if exact { passed = passed && best.assessments.first(where: { $0.goal == .preferredTime })?.penalty == 0 }
                    }
                }
                if name == "rain_exposure_unknown" { passed = passed && result.options.allSatisfy { $0.assessments.allSatisfy { $0.penalty == nil } } }
                rows.append(.init(name: name, day: day, status: result.status, options: result.options.count,
                                  firstVisitWIB: result.options.first.map { o in
                                      let m = Int(o.start.timeIntervalSince(ContextClock.day(day)!) / 60)
                                      return String(format: "%02d:%02d", m / 60, m % 60)
                                  }, firstPenalties: result.options.first?.assessments.map(\.penalty) ?? [],
                                  unknownGoals: result.options.first?.unknowns.count ?? 0, hardConstraintsPassed: passed, engineSeconds: seconds(began)))
            }
        }
        let reviews = snapshot.place.reviews ?? []
        return .init(observedAt: now.ISO8601Format(), placeID: id, liveDetailsRequests: client.requests, providerSeconds: providerSeconds,
                     reviewsReturned: reviews.count, reviewTimeHints: ReviewTimeExtractor.extract(reviews, now: now).count,
                     reviewAuthorsRetained: reviews.allSatisfy { $0.authorAttribution != nil },
                     currentHoursPresent: snapshot.place.currentOpeningHours != nil, regularHoursPresent: snapshot.place.regularOpeningHours != nil,
                     timeZonePresent: snapshot.place.timeZone?.id != nil || snapshot.place.utcOffsetMinutes != nil, cases: rows,
                     passed: rows.allSatisfy(\.hardConstraintsPassed))
    }
}
